# MoonFlame

**用纯 MoonBit 把「折叠栈」性能数据渲染成一张可交互的 SVG 火焰图。**

不依赖 Go、Node 或任何运行时——产物是单个文件，双击即看，可直接贴进 README。

![示例火焰图](examples/flame.png)

> 上图由 `moon run cmd/main -- testdata/demo.folded --out flame.svg` 生成，输入是真实采样数据。
> 想体验**点击缩放、Ctrl-F 搜索**等交互，请下载 [`examples/flame.svg`](examples/flame.svg) 用浏览器打开
> （内嵌脚本在 `<img>` 引用下不会执行，原因见[已知限制](#已知限制)）。

---

## 目录

- [这是什么](#这是什么)
- [主要功能](#主要功能)
- [快速验证](#快速验证)
- [完整流程](#完整流程)
- [命令行参数](#命令行参数)
- [差异火焰图](#差异火焰图)
- [已知限制](#已知限制)
- [目录结构](#目录结构)
- [开发](#开发)
- [参考与许可](#参考与许可)

---

## 这是什么

一个**渲染器**。输入折叠栈（folded stack）文本，输出一张能直接看的 SVG。

```
折叠栈文本  ──▶  MoonFlame  ──▶  单个 SVG 文件
```

折叠栈是 Brendan Gregg 定义的一种通用中间格式，每行一个调用栈加它的耗时：

```text
____moonbit__main;moonflame::demo::bench__sorting;bubble__sort;array::Array::at 73382500
```

`perf`、`py-spy`、`async-profiler`、`moon-pprof` 等工具都能产出它。所以 MoonFlame **不绑定任何语言或平台**。

**它不做采样**——那是上游工具的职责。它只负责把这些数据变成一张人一眼能看懂的图。

现有的可视化方案（`go tool pprof`、speedscope、Firefox Profiler）都需要额外运行时或浏览器会话；
MoonFlame 补的是「**单文件、零环境、可归档**」这一空缺。

## 主要功能

| 功能 | 说明 |
| --- | --- |
| **折叠栈解析** | 容忍超深栈（实测 7254 层）、超长单行（181K 字符）、空帧名等各种真实数据里的脏形状 |
| **调用树聚合** | 同父同名合并累加；计算自身耗时与累计耗时 |
| **限深合并** | 超过 `--max-depth` 的部分合并为 `(deeper)` 合成帧，**而不是丢弃**——否则深层耗时会被错算到最后一个可见帧上 |
| **布局** | 火焰图（根在底部）/ 冰柱图两种方向；按值比例切分，父宽严格等于子宽之和 |
| **可交互 SVG** | 经典火焰图配色 + 内嵌脚本：悬停信息栏、点击缩放、`Reset Zoom`、`Ctrl-F` 正则搜索、`Ctrl-I` 大小写开关、命中占比 |
| **差异火焰图** | 对比两份剖面，**红 = 变多、蓝 = 变少、白 = 无变化** |
| **文本热点报告** | `--top N` 直接打印 Top-N 自身耗时，不需要出图 |
| **确定性输出** | 同一输入必得逐字节相同的 SVG，可做快照测试与版本间对比 |
| **零依赖核心库** | 根包纯计算、无任何外部依赖；文件 IO 只出现在命令行入口 |

配色与交互行为对齐经典实现 `flamegraph.pl`，但对齐的只是**功能规格**——
其源码采用 CDDL-1.0，与本项目的 Apache-2.0 不兼容，因此一行未复制。详见 [参考与许可](#参考与许可)。

## 快速验证

**只想看看效果的话，不需要安装任何采样工具**——仓库里已带一份真实采样数据：

```powershell
moon run cmd/main -- testdata/demo.folded --out flame.svg
```

然后用浏览器打开 `flame.svg`。想看文本热点、不出图：

```powershell
moon run cmd/main -- testdata/demo.folded --top 10
```

仓库还带了两个用例，可以直接跑：

| 文件 | 用途 |
| --- | --- |
| `testdata/demo.folded` | ⭐ 主样例：32 栈 / 深度 3–13 / 1893 ms |
| `testdata/stress-recursive.folded` | 极限用例：79 栈 / 最深 **7254 层** / 5.5 MB，用来验证限深与合并 |

## 完整流程

想拿它分析**自己的程序**，走这条四步链路。以 MoonBit 程序为例：

**① 安装采样器**（仅采集端需要，渲染器不需要）

需要 [`mizchi/moon-pprof`](https://github.com/mizchi/moon-pprof)，它依赖 Rust 工具链。
完整安装步骤与踩坑记录见 [`docs/DATA-PIPELINE.md`](docs/DATA-PIPELINE.md)。

**② 把程序编译成 wasm-gc**

```powershell
moon build --target wasm-gc
```

> 必须用 wasm-gc：上游采样器基于 wasmtime，加载不了原生可执行文件。

**③ 采样并转成折叠栈**

```powershell
moon-pprof profile --wasm-gc _build/wasm-gc/debug/build/cmd/main/main.wasm --iterations 3 --out app.pb.gz
moon-pprof pprof2folded app.pb.gz app.folded
```

**④ 出图**

```powershell
moon run cmd/main -- app.folded --out flame.svg
```

`demo/` 目录里有一个可直接照抄的完整例子（四点负载 + 一键脚本）：

```powershell
powershell demo/reproduce.ps1     # 编译 → 采样 → 转折叠栈 → 打印热点
```

> 采样有随机性：重跑会得到不同的栈数与总耗时（实测行数 32–36、总耗时 1887–1917 ms），但**热点排序稳定**。
> 折叠栈里**一行 = 一个不同的调用栈**，重复出现的栈会被合并、权重累加，所以文件 32 行而原始样本有 490 个。

## 命令行参数

```text
moon run cmd/main -- <input> [options]        默认渲染模式
moon run cmd/main -- diff <before> <after> [options]
```

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `<input>` | 必填 | 折叠栈文件 |
| `-o, --out <path>` | 不输出 | SVG 输出路径；不传则只打印报告 |
| `--top <n>` | — | 打印前 N 个热点，可与 `--out` 同时用 |
| `--max-depth <n>` | `32` | 每个栈最多保留的帧数，`0` 表示不限制 |
| `--width <px>` | `1400` | 画布宽度 |
| `--inverted` | 关 | 输出冰柱方向（根在顶部）；默认是火焰图方向（根在底部） |

### 交互与配色

用浏览器直接打开生成的 SVG：

| 操作 | 效果 |
| --- | --- |
| 悬停 | 底部信息栏显示该帧的完整名字、耗时与占比 |
| 单击某帧 | 以它为根缩放展开；祖先帧变半透明，无关帧隐藏 |
| `Reset Zoom` | 复原到全图 |
| `Ctrl-F` / `Search` | 正则搜索，命中帧高亮为品红，右下角显示命中占比 |
| `Ctrl-I` / `ic` | 切换搜索是否区分大小写 |

配色沿用经典火焰图的**暖色调色板**（深红 → 橙 → 黄的单维渐变），同名帧同色，便于跨图追踪同一个函数。

## 差异火焰图

对比优化前后（或升级前后）两份剖面，把差异直接画进颜色里：

```powershell
moon run cmd/main -- diff testdata/demo-baseline.folded testdata/demo.folded -o flame-diff.svg
```

![差异火焰图](examples/flame-diff.png)

| 视觉通道 | 含义 |
| --- | --- |
| **宽度** | 按**当前**（第二个）剖面 —— 看清现在的时间花在哪 |
| 🔴 **红** | 该帧**变多了**（劣化），越红变化越大 |
| 🔵 **蓝** | 该帧**变少了**（改善） |
| ⚪ **白** | 变化可以忽略（注意不是灰色——灰字在浅色底上读不出来） |
| **悬停** | 额外显示带符号的变化量 |

颜色用全图最大的变化量做归一化——不归一化的话，只要有一处剧变，其它变化在颜色上就会全糊成一片。

> ⚠️ `testdata/demo-baseline.folded` 是**构造**的基线（含 `bubble__sort` 的行 ×3、含 `build__strings` 的行 ×0.8），
> 仅用于演示与测试差异模式，不是真实采样。规则固化在 `tools/make-baseline.js`，可逐行复核。

## 已知限制

1. **上游采样仅支持 wasm / wasm-gc** 目标，native CPU 采样不可用；
2. `moon-pprof` 需要 Rust 工具链（**仅采集端**）；**核心库零依赖**，只有命令行入口依赖官方包 `moonbitlang/x` 做文件读写；
3. 递归程序会产生极深栈（实测最深 7254 层），超过深度上限的部分合并显示为 `(deeper)`；
4. **上游采样分辨率取决于函数调用频率，而非运行时长**（实测：调用密集约 600 样本/秒，循环密集约 42 样本/秒，相差 14 倍）。因此短于约 25 ms 的函数可能采不到，且**延长运行时间不会提高统计质量**。详见 [`docs/DATA-PIPELINE.md`](docs/DATA-PIPELINE.md)；
5. 内嵌交互脚本**只在直接打开 SVG 或内联嵌入时执行**；用 `<img>` 引用（GitHub 渲染本 README 即是如此）时浏览器不会运行 SVG 内的脚本，只显示静态外观；
6. 帧的横轴按**耗时降序**排列（经典实现按名字字母序），这是为了让宽帧聚集在左侧、更易读的刻意选择；
7. 图中会出现 `(self)` 与 `(deeper)` 两个合成帧：前者是该函数的**自身耗时**，后者是超过深度上限被合并的更深帧。经典实现没有这两个节点，显式画出它们是为了保证「父矩形宽度 = 子矩形宽度之和」——否则图面上会出现空洞。

## 目录结构

```text
.
├── LICENSE                       Apache-2.0
├── folded.mbt                    折叠栈解析
├── calltree.mbt                  调用树聚合 / 限深合并 / 差异标注
├── hotspot.mbt                   Top-N 热点报告
├── layout.mbt                    矩形布局（火焰图 / 冰柱）
├── svg.mbt                       SVG 渲染（经典配色 + 内嵌交互脚本）
├── cli/                          命令行参数解析（独立包，可脱离文件系统测试）
├── cmd/main/                     入口：读文件 → 调用核心库 → 写文件
├── docs/
│   ├── DESIGN.md                 项目设计（定位、格式、算法、与经典实现的差异）
│   ├── DATA-PIPELINE.md          数据链路验证报告（含环境踩坑与关键发现）
│   └── APPLICATION.md            项目申报书
├── demo/                         演示负载（独立模块，可复现样例数据）
│   └── reproduce.ps1             一键复现脚本
├── examples/                     示例图（SVG 可交互，PNG 供 README 展示）
├── testdata/                     冻结的样例数据
└── tools/
    ├── analyze_folded.js         折叠栈结构分析
    └── make-baseline.js          构造差异模式基线
```

**分层原则**：根包只做纯计算、零外部依赖；参数解析单独成包以便脱离文件系统测试；
文件 IO 只出现在入口包——核心逻辑因此可以在没有文件系统的环境（如 wasm）里复用。

## 开发

```bash
moon check              # 类型检查
moon test               # 全部测试（122 个）
moon info && moon fmt   # 提交前更新接口并格式化
moon run cmd/main -- --help
```

## 参考与许可

本项目为**原创项目**，未复制任何第三方源码。

- 火焰图（Flame Graph）的概念与折叠栈格式由 **Brendan Gregg** 提出；
- 渲染外观与交互行为对齐 [brendangregg/FlameGraph](https://github.com/brendangregg/FlameGraph) 的 `flamegraph.pl`：**暖色调色板的数值公式、差异配色规则、以及悬停 / 点击缩放 / Ctrl-F 搜索的交互语义**均与之兼容。
  ⚠️ 该项目采用 **CDDL-1.0**（弱 copyleft），与本项目的 Apache-2.0 不兼容，因此**其源码一行未被复制**——只对齐功能规格，MoonBit 与 JavaScript 实现全部原创。详见 [`docs/DESIGN.md`](docs/DESIGN.md) §5b；
- 可选的上游数据来源：[mizchi/moon-pprof](https://github.com/mizchi/moon-pprof)（Apache-2.0），负责采样与格式归一；
- 渲染正确性以 [google/pprof](https://github.com/google/pprof)（Apache-2.0）作为交叉验证基准；
- `testdata/official-sample.wasm` 来自 moon-pprof 仓库的样例（Apache-2.0）。

本项目使用 [Apache License 2.0](LICENSE)。
