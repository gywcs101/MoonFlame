# MoonFlame 项目设计

> **一句话**：用纯 MoonBit 把「折叠栈」文本渲染成一张可交互的静态 SVG 火焰图。
>
> **工期目标**：2–4 天净工时（AI 辅助），不追奖，只求主题合理、难度低、逻辑闭环、能过验收。
>
> **文档状态**：本文件已合并并取代早期探索文档。数据链路的实测结论见 `docs/DATA-PIPELINE.md`。

---

## 1. 项目定位与边界

| ✅ 做什么 | ❌ 不做什么 |
| --- | --- |
| 解析折叠栈文本 | 不做采样（操作系统 / moon-pprof 的职责） |
| 聚合成调用树，算自身耗时与累计耗时 | 不解析 perf.data / pprof / JFR 等二进制格式 |
| 计算布局（每个矩形的坐标） | 不做完整 Web 应用（不做拖拽缩放搜索） |
| 输出可交互的静态 SVG | 不依赖 Go / Node / 浏览器服务 |
| 文本 Top-N 热点、两份剖面差异对比 | 不做多语言格式大全（只给转换配方） |

**边界一句话**：别人负责拿到数据，MoonFlame 负责最后一公里——把数据变成**单个文件、零环境、可归档、可贴进 README** 的图。

### 为什么这个定位成立

现有的可视化方案都需要额外运行时：`go tool pprof` 要 Go 并起本地服务、speedscope 要开网页、Firefox Profiler 要浏览器会话。
MoonFlame 补的是「单文件、零环境」这一空缺，而且**实现语言是 MoonBit**（赛事主题），生态内检索 `flamegraph` / `folded` / `pprof` 均为 0 命中。

---

## 2. 数据链路

```text
【路径二 · 主链路：真实采样，不改被测程序一行代码】
  MoonBit wasm-gc 程序
      → moon-pprof profile --wasm-gc app.wasm --out app.pb.gz
      → moon-pprof pprof2folded app.pb.gz app.folded
      → app.folded ──┐
                     │
【路径一 · 兜底：自带插桩，跨平台、零依赖】          │
  用户程序 + PhaseRecorder 插桩库 → folded ────────┤
                                                  ↓
                                 MoonFlame（纯 MoonBit，零依赖）
                                                  ↓
                                          flame.svg（可交互）
```

两条路径产出**同一格式**，渲染器只认折叠栈，互不干扰——这反过来证明了格式选择的正确性。

### 上游工具：mizchi/moon-pprof（Apache-2.0）

| 项 | 说明 |
| --- | --- |
| 定位 | 数据生产者 + 格式转换器；**不画火焰图**（可视化交给 `go tool pprof` / speedscope） |
| 我们调用 | `profile --wasm-gc`（采样）、`pprof2folded`（转折叠栈） |
| 我们不调用 | `summary` / `bench` / `memprofile*` / 各类 `*2pprof` 转换器 |
| 采样方式 | wasmtime GuestProfiler + epoch 中断，默认间隔 1000 µs，**采样开销约 10–15%** |
| 限制 | CPU 采样**仅支持 wasm / wasm-gc**（native 的 CPU 采样不可用）；采样密度取决于函数调用频率，循环密集代码会被欠采样（详见 `docs/DATA-PIPELINE.md` §9.3） |
| 许可证 | Apache-2.0（需在 README 的「参考来源」中声明） |
| 验证状态 | ✅ 全链路已实测跑通：官方样例 + **自建 wasm-gc 程序**均能正常采样、符号可读，并用 `go tool pprof` 交叉验证一致 |

---

## 3. 输入格式规范

```text
<帧1>;<帧2>;<帧3>;<...> <权重>
```

- 帧之间用分号 `;` 分隔；栈与权重之间用**一个空格**
- 一个样本一行，**不做聚合**（相同栈会重复出现，聚合由 MoonFlame 负责）
- 权重：moon-pprof 输出的是**纳秒时间**（实测总和与 `go tool pprof` 报告的 `Total samples` 精确一致）
- 与 FlameGraph 定义的折叠栈完全兼容

### 实测数据的三个特征（决定了实现细节）

| 特征 | 实测值 | 对实现的要求 |
| --- | --- | --- |
| 栈极深（递归） | 最深 **7254 层**，中位 2735 层 | **必须限深 + 深部合并**（见 §4.3） |
| 行数 ≠ 规模 | **79 行 = 5.52 MB**（最长单行 181,350 字符） | 逐行流式读取，不假定行长上限 |
| 帧名有瑕疵 | 根帧 `____moonbit__main`；`mandel__point`（下划线双写）；部分栈以**空帧名**开头 | 空帧名兜底；可选 `--undouble` 折叠 `__` → `_` |

---

## 4. 核心算法

### 4.1 解析

逐行处理，`lastIndexOf(' ')` 切出权重，其余按 `;` 切帧。空帧名映射为 `(root)`。

### 4.2 聚合为树

```moonbit
pub struct Node {
  name : String
  value : Double                 // 累计值（含子节点）
  children : Map[String, Node]   // 同父同名合并
}
```

⚠️ **合并只能在同父同名的兄弟之间生效，无法折叠递归链**。`ackermann@2` 的父是 `ackermann@1`，`ackermann@3` 的父是 `ackermann@2`——每层都是不同节点。所以必须配合限深。

⚠️ `Map` 遍历顺序不稳定，**渲染前必须排序**，否则输出抖动、快照测试随机失败。

### 4.3 深度限制与深部合并（本项目最关键的设计）

真实递归数据可达 7254 层。若每层 20px，图高 145,000px，完全不可用。

**限制深度时不能简单丢弃**，否则父节点宽度小于子节点之和，布局出现空洞。正确做法：

- 深度 ≥ `--max-depth` 的帧**合并进一个合成节点**（如 `(…deeper)`），把值累加进去；
- 这样保证不变量「**父节点宽度 = 所有子节点宽度之和**」恒成立。

同理，栈停在中间产生的「自身耗时」要用 `(self)` 伪节点补齐，否则同样破坏该不变量。

### 4.4 布局（icicle / 火焰图）

算法本身很简单，**不需要任何矩形打包算法**：

1. 总宽 `W`，行高 `rowH`；深度 `d` 的帧画在 `y = d * row_h`
2. 根节点占满 `[0, W]`
3. 子节点**按 value 降序**，按比例瓜分父节点区间
4. 子节点从父节点左边界依次累加
5. ⭐ **最后一个子节点的右边界直接取父节点的右边界**（消除浮点累加误差）
6. 宽度 < 1.5px 的矩形跳过

> icicle 方向根在顶部（`y = depth * row_h`），经典火焰图根在底部（翻转 y）。加个 `--inverted` 即可支持两种。

**算例**（`W=600`，`rowH=20`）：

| 节点 | 区间来源 | 比例 | 结果矩形 (x, y, w, h) |
| --- | --- | --- | --- |
| `main` | — | 100% | (0, 0, 600, 20) |
| `compute` | main [0,600] | 1000/1500 | (0, 20, 400, 20) |
| `read_file` | main [0,600] | 500/1500 | (400, 20, 200, 20) |
| `fft` | compute [0,400] | 900/1000 | (0, 40, 360, 20) |
| `(self)` | compute [0,400] | 100/1000 | (360, 40, 40, 20) |

### 4.5 SVG 输出

**核心认知：SVG 就是 XML 文本，用 `StringBuilder` 拼字符串即可，没有任何图形库。**

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="600" height="60" viewBox="0 0 600 60">
  <rect x="0" y="0" width="600" height="19" fill="hsl(212,62%,68%)" stroke="#fff">
    <title>main — 1500 (100%)</title>
  </rect>
</svg>
```

要点：
- **悬停提示** = 矩形的 `<title>` 子元素，**零 JS 即得交互**
- **颜色** = `hsl(名字哈希 % 360, 62%, 68%)` → 同名同色，跨图对比友好（颜色本身无语义）
- `height = h - 1` 留 1px 白缝，是「能看」与「好看」的分界
- `viewBox` 与 `width/height` 分离，缩放不失真
- **XML 转义**：`&` 必须**第一个**替换（`&` → `&amp;`，`<` → `&lt;`，`>` → `&gt;`）
- **体积控制**：按颜色分组 `<g fill="...">` 或 CSS class，比每个矩形重复写 `fill` 省很多；坐标取整
- **文字标签**：SVG 不会自动排版，`<text>` 的 `y` 是**基线**不是顶边；宽度不够就干脆不画标签
- 可选加分项：内嵌 30–80 行 JS 做搜索框高亮

### 4.6 确定性输出

同输入必得同输出。措施：目录/Map 遍历一律先排序、tie-breaker 用字典序、避免任何系统时间或随机源。这是快照测试与版本对比的前提。

---

## 5. 项目结构

```text
moonflame/
├── LICENSE                      # MIT
├── README.md
├── moon.mod                     # 依赖 moonbitlang/x（仅 CLI 需要）
├── moon.pkg                     # 根包：纯渲染逻辑，零依赖
│
├── folded.mbt                   # 折叠栈解析
├── calltree.mbt                 # 调用树聚合 / 限深合并 / 差异标注
├── unit.mbt                     # 权重单位与格式化（时间自动缩放、计数加千分位）
├── names.mbt                    # 符号名归一化（__ 折叠 / 长度前缀 demangle）
├── hotspot.mbt                  # Top-N 热点报告
├── report.mbt                   # 文本报告：调用关系 / 差异排行 / 栈过滤
├── layout.mbt                   # 矩形布局（火焰图 / 冰柱两种方向）
├── svg.mbt                      # SVG 渲染（经典配色 + 内嵌交互脚本）
├── *_test.mbt                   # 黑盒测试
│
├── cli/                         # 命令行参数解析（独立包，可单独测试）
├── cmd/main/                    # 入口：读文件 → 调用核心 → 写文件
│
├── demo/                        # 演示负载（独立模块，产出样例数据）
│   ├── demo.mbt                 # 4 个阶段：排序 / 字符串 / 矩阵 / 递归
│   └── reproduce.ps1            # 一键复现：编译 → 采样 → 转折叠栈
│
├── examples/                    # 示例图（SVG 可交互，PNG 供 README 展示）
└── testdata/
    ├── demo.folded              # ⭐ 主 demo 数据：32 栈 / 深度 3–13 / 1893ms
    ├── demo-baseline.folded     # 构造的基线，用于演示差异模式（非真实采样）
    ├── stress-recursive.folded  # ⭐ 极限用例：79 栈 / 最深 7254 层 / 5.5MB
    └── official-sample.wasm, .pb.gz  # 上游样例（Apache-2.0，注明来源）
```

**分层原则**：根包只做纯计算、零外部依赖；参数解析单独成包以便脱离文件系统测试；
文件 IO 只出现在入口包。这样核心逻辑可以在没有文件系统的环境（如 wasm）里复用。

**CLI 设计**：

```bash
moonflame <input> --out flame.svg                     # 渲染（默认命令）
moonflame hotspots <input> --top 10                   # 热点榜
moonflame callers  <input> <name>                     # 谁调用了它
moonflame callees  <input> <name>                     # 它调用了谁
moonflame diff     <before> <after> --out diff.svg    # 差异火焰图
moonflame delta    <before> <after> --top 10          # 差异文本排行
moonflame filter   <pattern> <input> -o sub.folded    # 栈过滤
moonflame <input> --unit ms --max-depth 8 --inverted --width 1000
```

**顶层只有 5 个选项/开关**：`<input>`（位置参数）、`--out`、`--max-depth`、`--width`、
`--unit`、`--inverted`。一切**文本报告**都是子命令——这是让接口面不随功能增长的
关键设计：新增分析能力时，顶层界面保持不变。原先的 `--top` 已移入 `hotspots`。

`filter` 的输出是**折叠栈文本**而非图片，因此可以就地串起来：
`filter ... -o sub.folded` 之后再用默认命令出图。

---

## 5b. 与经典实现的差异

图形外观与交互对齐 Brendan Gregg 的 **FlameGraph**（`flamegraph.pl`）：调色板公式、
差异配色、悬停 / 点击缩放 / Ctrl-F 搜索的行为都与之兼容。

> ⚠️ **未复制其源码。** 那个项目采用 **CDDL-1.0**——一种**文件级弱 copyleft**，
> 不是宽松许可（它与 GPL 明确不兼容；与宽松许可混用也存在法律不确定性）。
> 为避免任何许可证混用问题，今后也**不要**把它的代码贴进来。
> 我们只对齐*功能规格*（配色数值、交互语义、几何常量），
> 所有 MoonBit 与 JavaScript 实现均为原创。

### 已对齐

| 项 | 做法 |
| --- | --- |
| 暖色调色板 | 用它的 `hot` 公式：`r = 205+50v`、`g = 230v`、`b = 55v`，三通道共用同一个 `v`，因此是**深红 → 橙 → 黄**的单维渐变 |
| 差异配色 | 用它的 `color_scale`：白底，`红 = 变多`、`蓝 = 变少`、**`白 = 无变化`**（不是灰色） |
| 内嵌 JS 交互 | 悬停信息栏、点击缩放、Reset Zoom、Ctrl-F 搜索、Ctrl-I 大小写、命中占比 |
| 标题栏 | `Flame Graph` / `Icicle Graph`（按方向自动切换），圆角矩形 `rx=2` |
| 几何常量 | 行高 16、字号 12、左右留白 10、帧间留缝 1px、`minwidth` 0.1px |
| 浅色背景 | `#eeeeee → #eeeeb0` 渐变——差异模式下「无变化」是纯白，**没有底色那些帧会看不见** |

### 仍然偏离或未实现

| # | 项 | 说明 |
| --- | --- | --- |
| 1 | **配色哈希** | 它的默认走 Perl 的 `srand`/`rand`，跨 Perl 构建不稳定（同一输入可能出不同颜色）。我们改用它的 `sum_namehash` 作种子 + drand48（多数平台上 Perl 实际用的 PRNG）复现，观感一致但**确定性**。它的 `namehash()` 不能用——那个函数只读前三个字符，而 MoonBit 函数名普遍以 `moon`/`array` 开头，会算出大量同色 |
| 2 | **帧的横轴顺序** | 我们按耗时降序，它按名字字母序。刻意选择：宽帧聚在左侧更好读 |
| 3 | **`(self)` 合成帧** | 它没有这个节点。我们显式画出自身耗时，用来保证「父矩形宽度 = 子矩形宽度之和」这一不变量 |
| 4 | **差异模式只出一个方向** | 它的建议是交换两份文件再生成一张，从另一个方向看「消失的帧」 |

### 交互的适用范围

内嵌脚本只在 SVG 被**直接打开或以内联方式嵌入**时执行。
用 `<img src="x.svg">` 引用（GitHub 渲染 README 就是这么做的）时浏览器**不会运行其中的脚本**——
这是 SVG 规范的既定行为，不是缺陷。因此 README 里嵌的图只有静态外观，
要体验交互需把 `examples/flame.svg` 下载后直接打开。

### 5c. 范围取舍记录

功能增长过程中**主动放弃**的几项，理由记在这里，避免日后重复讨论：

| 放弃的 | 理由 |
| --- | --- |
| **CLI 侧的正则匹配** | 若让 `filter` 支持正则，就得自己实现一个正则引擎（约 400+ 行，且边界情况极易出错）。改为**子串匹配**——等价于 `grep` 的默认行为，覆盖绝大多数真实用法，风险归零。需要正则时仍可用 `grep` 管道，而 SVG 内嵌的搜索**是**正则（浏览器自带引擎，零成本） |
| `--json` 导出 | 需求较推测；且要先定一套稳定的格式契约，属于「有了真实消费方才做」的事 |
| 多文件合并 | 价值中等，但会再引入一个顶层入口 |
| 小帧合并（`--min-percent` → `(others)`） | 需要新参数；而渲染层已经按 `minwidth` 丢弃不可见矩形，视觉收益有限 |

**行数与红线的冲突**：`AGENTS.md` 第 5 条要求核心库不超过 800 行，而比赛章程的项目规模
参考值是 4~10k 有效代码行，两者方向相反。本项目选择向参考规模靠拢，当前核心库约 1379 行
代码（其中 233 行是内嵌 JS 字面量）。若要守回 800 行，应**砍功能而不是注水**，
可优先考虑：`report.mbt` 的 `callers`/`callees`（与 `hotspots` 有部分重叠）、
`names.mbt` 的长度前缀还原（收益依数据形态而定）。

---

## 6. MoonBit API 速查（已逐条核对官方源码）

### 6.1 字符串：三个长度必须分清

| 表达式 | 含义 | `"你好abc"` | `"a👨b"` |
| --- | --- | --- | --- |
| `s.length()` | UTF-16 码元数 | 5 | 4 |
| `s.char_length()` | Unicode 码点数 | 5 | 3 |
| 显示宽度 | 需自己算 | 7 | 4 |

```moonbit
for c in s { ... }                 // Iter[Char]
let chars : Array[Char] = s.to_array()
let parts : Iter[StringView] = s.split(";")
let t : StringView = s.trim_space()
let sub = s.substring(start=0, end=2)
parse_double(sv)                   // StringView -> Double raise（返回值，函数需带 raise）
parse_int(sv)
String::from_array(chars)
```

### 6.2 拼接与集合

```moonbit
let sb = StringBuilder()           // 注意：不是 StringBuilder::new()
sb.write_string("x"); sb.write_char(';'); sb.to_string()

let a : Array[Rect] = Array::new()
a.push(r); a.length(); a.map(f); a.filter(f)
a.each(f); a.fold(init=0.0, fn(acc, x) { acc + x.value })
a.sort_by(fn(x, y) { if x.value > y.value { -1 } else if x.value < y.value { 1 } else { 0 } })
Array::clamped_view(chars, start=i, end=j)   // 数组没有切片语法

let m : Map[String, Node] = Map::new()
m.set(k, v); m.get(k)              // 返回 V?
m.each(fn(k, v) { ... })           // ⚠️ 顺序不稳定，输出前必须排序
```

### 6.3 命令行与测试

```moonbit
// moon.pkg
import { "moonbitlang/core/argparse", "moonbitlang/core/env" }
options("is-main": true)           // 当前版本模板用这个；旧文档写的 pkgtype(kind:"executable") 已过时

fn main {
  let argv = @env.args()
  let matches = @argparse.parse(command(), argv~)
  guard matches.values is { "input": [input], "out"? : outs, .. } else { fail("缺少 input") }
}
```

```moonbit
test "解析折叠栈" {
  inspect(parse("a;b 3\na;c 7").length(), content="2")   // 先写 inspect(...)，再 moon test --update
}
```

- `_test.mbt` 黑盒测试（只能访问 pub 成员）；`_wbtest.mbt` 白盒测试
- `README.mbt.md` 里的 ` ```mbt check ` 代码块会被 `moon test` **真实执行** → 白拿一份「可运行示例」

### 6.4 容易记错的 API

| 你可能会写 | 实际正确写法 | 说明 |
| --- | --- | --- |
| `Int::to_char(i)` | `Char::from_int(i)` | `Int::to_char` 返回 `Char?` |
| `d.clamp(0.0, 1.0)` | `d.clamp(min=0.0, max=1.0)` | clamp 用命名参数 |
| `for i in 0..4` | `for i in 0..<4` | 范围只有 `..<`、`..<=`、`>..`、`>=..` |
| `arr[a:b]` | `Array::clamped_view(arr, start=a, end=b)` | 数组无切片语法；`String` 才有 `s[a:b]` |
| `sv.to_string()` | `.to_owned()` | StringView → String 的明确方法 |
| 遍历 Map 直接输出 | 先排序再输出 | 否则快照测试随机失败 |
| `parse_double(s)` 当纯函数 | 它 `raise`，所在函数要带 `raise` | 同 `parse_int` |

---

## 7. 三天工作分解

| 时间 | 目标 | 完成标志 |
| --- | --- | --- |
| **Day 0（1 小时）** | `moon new`、推 GitHub、放 LICENSE、README 写定位 | 仓库公开可访问，`moon test` 能跑 |
| **Day 1** | 解析 + 聚合 + 限深合并（纯函数） | 用 `testdata/demo.folded` 与 `testdata/stress-recursive.folded` 都能跑通，能打印 Top-N 文本 |
| **Day 2** | 布局 + SVG 输出 + CLI | `moon run cmd/main -- render testdata/demo.folded --out flame.svg` 出图，浏览器可打开 |
| **Day 3** | 收尾 | 差异对比、错误提示、README 示例（被 `moon test` 验证）、AI 使用说明、分 6–10 次提交 |

---

## 8. 防膨胀红线（建议写进仓库 `AGENTS.md`）

1. 不新增第 2 个第三方依赖
2. 不做配置文件格式（要可配置就用命令行参数）
3. 命令行参数不超过 5 个
4. 不做 Web/浏览器演示
5. 核心库超过 800 行即视为范围失控，回头砍功能
6. 只支持默认后端，不加条件编译

---

## 9. 验收对照

| 验收标准 | 本项目的落实 |
| --- | --- |
| MoonBit 为主 | 全部 `.mbt`，无 FFI、无其他语言。交互脚本是内嵌在 SVG 字符串里的 JS **字面量**，不参与构建、也不引入任何依赖 |
| 仓库公开 | GitHub 公开仓库，18 个提交，均为真实开发步骤（无拆分凑数、无空提交） |
| 能够运行 | `moon run cmd/main -- testdata/demo.folded --out flame.svg` 一条命令出图；`moon test` 122 个全绿；README 里的示例命令均实测可执行 |
| 工作有效 | 原创项目；核心库约 956 行代码（含 233 行内嵌 JS，纯 MoonBit 逻辑约 723 行）+ 约 1284 行测试，附完整文档与可复现的样例数据 |
| 开源合规 | MIT。**未复制任何第三方源码**；与 `flamegraph.pl` 对齐的只有功能规格——该项目采用 CDDL-1.0（文件级弱 copyleft，非宽松许可），已在 README 与 §5b 明确声明 |
| AI 可解释 | `AGENTS.md` 载明 AI 使用约定（逐条测试验证、关键结论必须实测）；实测结论记录在 `docs/DATA-PIPELINE.md` |

---

## 10. 页面限制

README 的「已知限制」一节共列 7 条，涵盖采样目标限制、采集端依赖、极深栈合并、
采样分辨率的反直觉行为、内嵌脚本的生效条件、横轴排序口径，以及两个合成帧的含义。
此处不重复，以免两处描述随时间漂移。

