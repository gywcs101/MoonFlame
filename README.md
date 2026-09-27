# MoonFlame

**用纯 MoonBit 把「折叠栈」性能数据渲染成一张可交互的静态 SVG 火焰图。**

不依赖 Go、Node 或任何运行时——产物是单个文件，双击即看，可直接贴进 README。

---

## 项目状态

| 部分 | 状态 |
| --- | --- |
| 数据链路（采样 → 折叠栈） | ✅ 已跑通并交叉验证 |
| 演示负载与样例数据 | ✅ 已完成（`demo/` + `testdata/`） |
| 渲染器主体（解析 / 聚合 / 布局 / SVG） | 🚧 开发中 |

> 当前仓库已包含可复现的数据链路与真实样例数据；渲染器代码正在开发。使用示例将在渲染器落地后补充。

---

## 它做什么 / 不做什么

| ✅ 做 | ❌ 不做 |
| --- | --- |
| 解析折叠栈文本 | 不做采样（那是操作系统 / moon-pprof 的职责） |
| 聚合成调用树，算自身耗时与累计耗时 | 不解析 perf.data / pprof 等二进制格式 |
| 计算布局，生成可交互的静态 SVG | 不做 Web 应用、不做拖拽缩放 |
| 文本 Top-N 热点、两份剖面差异对比 | 不依赖 Go / Node / 浏览器服务 |

**定位**：现有的可视化方案（`go tool pprof`、speedscope、Firefox Profiler）都需要额外运行时或浏览器会话；MoonFlame 补的是「单文件、零环境、可归档」这一空缺。

---

## 数据从哪来

MoonFlame 只接受**折叠栈（folded stack）**这一通用中间格式：

```text
____moonbit__main;moonflame::demo::bench__sorting;bubble__sort;array::Array::at 73382500
```

该格式由 FlameGraph 定义，`perf`、`py-spy`（raw）、`async-profiler`（collapsed）、`mizchi/moon-pprof`（`pprof2folded`）等均可产出。

### 复现本项目使用的样例数据

`demo/` 是一个 MoonBit 演示负载（排序 / 字符串 / 矩阵 / 递归四个阶段），可按脚本一键复现采样数据：

```powershell
# 需要先安装 moon-pprof，见 docs/DATA-PIPELINE.md
pwsh demo/reproduce.ps1
```

脚本会：编译 `wasm-gc` → 用 `moon-pprof` 采样 → 转成折叠栈 → 输出热点概览。
生成的 `demo.folded` 即可作为渲染器的输入。

---

## 目录结构

```text
.
├── LICENSE                      Apache-2.0
├── docs/
│   ├── DESIGN.md                项目设计（定位、格式、算法、实现要点）
│   ├── DATA-PIPELINE.md         数据链路验证报告（含环境踩坑与关键发现）
│   └── APPLICATION.md           项目申报书
├── demo/                        演示负载（MoonBit，可复现样例数据）
│   └── reproduce.ps1            一键复现脚本
├── testdata/
│   ├── demo.folded              ⭐ 主样例：32 栈 / 深度 3–28 / 888ms
│   ├── stress-recursive.folded  极限用例：79 栈 / 最深 7254 层
│   └── official-sample.*        上游样例（Apache-2.0）
└── tools/
    ├── analyze_folded.js        折叠栈结构分析
    └── check_topic.js           生态撞车自查（mooncakes.io）
```

---

## 已知限制

1. 上游采样**仅支持 wasm / wasm-gc** 目标，native CPU 采样不可用；
2. `moon-pprof` 需要 Rust 工具链，但**仅用于采集端**；渲染器本身零依赖；
3. 递归程序会产生极深栈（实测最深 7254 层），超过深度上限的部分将被合并显示；
4. **上游采样分辨率取决于函数调用频率，而非运行时长**（实测：调用密集约 600 样本/秒，循环密集约 42 样本/秒，相差 14 倍）。因此短于约 25ms 的函数可能采不到，且**延长运行时间不会提高统计质量**。详见 [docs/DATA-PIPELINE.md](docs/DATA-PIPELINE.md)。

---

## 参考与许可

本项目为**原创项目**，未复制任何第三方源码。

- 火焰图（Flame Graph）的概念与折叠栈格式由 **Brendan Gregg** 提出，本项目仅采用该公开格式与图形概念；
- 可选的上游数据来源：[mizchi/moon-pprof](https://github.com/mizchi/moon-pprof)（Apache-2.0），负责采样与格式归一；
- 渲染正确性以 [google/pprof](https://github.com/google/pprof)（Apache-2.0）作为交叉验证基准；
- `testdata/official-sample.wasm` 来自 moon-pprof 仓库的样例（Apache-2.0）。

本项目使用 [Apache License 2.0](LICENSE)。
