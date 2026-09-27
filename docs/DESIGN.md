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
├── LICENSE                  # Apache-2.0
├── README.mbt.md            # 代码块会被 moon test 真实执行
├── moon.mod
├── moon.pkg
├── moonflame.mbt            # 核心：解析 / 聚合 / 布局
├── svg.mbt                  # SVG 渲染
├── moonflame_test.mbt       # 黑盒测试
├── cmd/main/
│   ├── moon.pkg             # options("is-main": true)
│   └── main.mbt             # 入口：一条命令出结果
├── demo/                    # 演示负载（MoonBit，可复现 demo 数据）
│   ├── demo.mbt             # 4 个阶段：排序 / 字符串 / 矩阵 / 递归
│   └── reproduce.ps1        # 一键复现：编译 → 采样 → 转折叠栈
└── testdata/
    ├── demo.folded          # ⭐ 主 demo 数据：33 栈 / 深度 3–29 / 894.6ms
    ├── demo.wasm, demo.pb.gz
    ├── stress-recursive.folded  # ⭐ 极限用例：79 栈 / 最深 7254 层 / 5.5MB
    └── official-sample.wasm, .pb.gz  # 上游样例（Apache-2.0，注明来源）
```

**CLI 设计（参数不超过 5 个）**：

```bash
moonflame render input.folded --out flame.svg
moonflame render input.folded --max-depth 32 --inverted
moonflame render input.folded --top 10          # 只输出文本热点
moonflame diff before.folded after.folded --out diff.svg
```

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
| MoonBit 为主 | 全部 `.mbt`，无 FFI、无其他语言 |
| 仓库公开 | GitHub 公开，3–4 天内分 6–10 次提交 |
| 能够运行 | `moon run cmd/main -- render ...` 一条命令出图 + `moon test` 全绿 + README 示例可执行 |
| 工作有效 | 原创项目；mooncakes.io 检索 `flamegraph`/`folded`/`pprof` 均 0 命中（证据见 `tools/check_topic.js`） |
| 开源合规 | Apache-2.0；README 声明 moon-pprof 与 Brendan Gregg 的参考来源 |
| AI 可解释 | README 写明 AI 参与范围与逐条验证方式 |

---

## 10. README 必写的四条限制

1. 采样**仅支持 wasm / wasm-gc** 目标（native CLI 的 CPU 采样不可用）；
2. 需要 Rust 工具链**仅用于采集端**；渲染器本身零依赖；
3. 递归程序会产生极深栈，超过 `--max-depth` 的部分会被合并显示；
4. **上游采样分辨率很粗，且取决于函数调用频率而非运行时长**（实测：调用密集约 600 样本/秒，循环密集约 42 样本/秒，相差 14 倍；`--interval-us` 与 `--iterations` 几乎不改变样本数）。含义：**短于约 25ms 的函数可能完全采不到；跑久一点也不会提高统计质量。** 详见 `docs/DATA-PIPELINE.md` §9.3。

---

## 11. 备选主题（未启动，仅备查）

早期评估过、目前**未启动**的方向：moonwidth（CJK 终端宽度）、moonchangelog（提交信息→CHANGELOG）、mooncaptcha（验证码）、moonglow（Markdown→终端）、moonctx（LLM 上下文打包）。
详细设计见 仓库外的归档目录（未纳入版本控制）。
