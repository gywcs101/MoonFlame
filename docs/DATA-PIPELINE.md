# MoonFlame 数据链路验证报告

> **验证时间**：2026-09-19
> **验证目标**：确认 `mizchi/moon-pprof` → folded → 自研火焰图渲染器 这条数据链路能否跑通
> **结论**：✅ **跑通了**，且用 `go tool pprof` 做了交叉验证，数据一致。
> **但**：真实数据暴露了一个必须在渲染器里解决的结构性问题（见"关键发现 3"）。

---

## 1. 结论速览

| 验证项 | 结果 |
| --- | --- |
| Rust 工具链（工作区内安装，不动系统） | ✅ rustc 1.98.1 (GNU) |
| `moon-pprof` v0.1.3 从源码编译 | ✅ 离线编译 6m43s，产出 44.6MB 可执行文件 |
| 采样 MoonBit wasm-gc 程序 | ✅ 81 samples / 139.55 ms |
| MoonBit 符号还原（demangle） | ✅ 得到 `mizchi::bench::ackermann` 等可读名字 |
| `pprof2folded` 导出折叠栈 | ✅ 格式正确，0 解析失败行 |
| 与 `go tool pprof` 交叉验证 | ✅ **数值完全一致** |
| 格式能否直接作为渲染器输入 | ✅ **可以**（分号分隔 + 值） |
| 数据规模是否符合预期 | ⚠️ **栈深度是致命量级（最深 7254 层）** |

---

## 2. 环境变更清单（可完整回滚）

所有东西都装在**工作区内**，没有污染系统目录：

| 路径 | 内容 | 大小 |
| --- | --- | --- |
| `_toolchain/rustup/` | Rust 工具链（RUSTUP_HOME） | ~200 MB |
| `_toolchain/cargo/` | cargo 家目录 + 已装二进制（CARGO_HOME） | ~50 MB |
| `_toolchain/target/` | 编译缓存（CARGO_TARGET_DIR） | 数百 MB |
| `_toolchain/cargo/bin/moon-pprof.exe` | **产出的工具** | 44.6 MB |
| `testdata/` | 测试数据 | main.wasm / main.pb.gz / main.folded |

**回滚方式**：直接删除 `_toolchain` 目录即可，系统无残留（未写入 PATH、未改注册表、未装 MSVC）。

> ⚠️ 注意：`_toolchain/target` 体积较大且可重建，建议加进 `.gitignore`，不要提交。

---

## 3. 完整可复现命令

### 3.1 一次性安装（约 10 分钟）

```powershell
$root = "D:\DSH项目\Moonbit黑客松\_toolchain"
$env:RUSTUP_HOME = "$root\rustup"
$env:CARGO_HOME  = "$root\cargo"
$env:CARGO_TARGET_DIR = "$root\target"
$env:PATH = "$root\cargo\bin;E:\mingw64\bin;$env:PATH"

# ① 下载 rustup-init（必须用 -gnu 版，因为本机只有 MinGW，没有 MSVC）
#    下载地址：https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-gnu/rustup-init.exe
& "$root\rustup-init.exe" -y --no-modify-path --profile minimal `
    --default-host x86_64-pc-windows-gnu `
    --default-toolchain stable-x86_64-pc-windows-gnu

# ② 编译安装（首次会下载约 200 个依赖）
cargo install moon-pprof --locked
```

### 3.2 每次使用的链路

```powershell
$root = "D:\DSH项目\Moonbit黑客松\_toolchain"
$env:PATH = "$root\cargo\bin;E:\mingw64\bin;$env:PATH"

# ① 采样：跑 wasm-gc 二进制并生成 pprof
moon-pprof profile --wasm-gc main.wasm --out main.pb.gz

# ② 看 Top-N 热点（验证 demangle）
moon-pprof summary main.pb.gz

# ③ 转折叠栈 —— 这就是喂给自研渲染器的
moon-pprof pprof2folded main.pb.gz main.folded

# ④ 交叉验证（可选，需要 go）
go tool pprof -top main.pb.gz
```

---

## 4. 交叉验证证据

同一份 `main.pb.gz`，两个独立工具的结果：

| 函数 | `moon-pprof summary` | `go tool pprof -top` | 一致？ |
| --- | --- | --- | --- |
| `mizchi::bench::ackermann` | 116.81 ms (83.7%) | 116.81 ms (83.71%) | ✅ |
| `mizchi::bench::fib` | 12.28 ms (8.8%) | 12.28 ms (8.80%) | ✅ |
| `mizchi::bench::mandel__point` | 10.46 ms (7.5%) | 10.46 ms (7.50%) | ✅ |
| `____moonbit__main`（根） | — | 0 flat / 139.55 cum | ✅ |
| **总计** | **139.55 ms** | **139.55 ms** | ✅ |

→ 数据可信，可作为渲染器的**正确性基准（oracle）**。

---

## 5. 关键发现（5 条，直接决定渲染器设计）

### 发现 1：格式兼容，确认无疑 ✅

`main.folded` 内容形如：

```text
____moonbit__main;mizchi::bench::mandel__sum;mizchi::bench::mandel__point 10461800
____moonbit__main;mizchi::bench::fib;mizchi::bench::fib;...;mizchi::bench::fib 3088500
```

- 分号分隔调用栈 + 空格 + 值 —— **与 FlameGraph 标准折叠栈完全一致**
- 79 行全部解析成功，**0 失败**
- 结论：**渲染器的输入格式设计是对的，不需要改**

### 发现 2：值（第 2 列）是**纳秒时间**，不是采样次数

- 总和 `139545300` = 139.55 ms，与 `summary` 的 "Total: 139.55 ms" 精确对应
- 结论：渲染器应把该值当**不透明的权重**（只用比例），并支持 `--unit` 标注；不要假设它是整数计数（应能解析浮点）

### 发现 3：⚠️ 栈深度是致命量级 —— 必须做深度限制

这是本次验证**最重要的发现**：

| 指标 | 值 |
| --- | --- |
| 最深栈 | **7,254 层** |
| 中位深度 | **2,735 层** |
| p90 深度 | 5,485 层 |
| 深度 > 100 的样本 | **72 / 79** |
| 文件大小 | **5.52 MB**（仅 **79** 个样本！） |
| 最长单行 | **181,350 字符** |

**原因**：`ackermann` 是递归函数，采样抓到的栈是

```text
____moonbit__main;ackermann;ackermann;ackermann;...（重复数千次）...;ackermann
```

单帧名 `mizchi::bench::ackermann` 出现 **231,517 次**。

**三个直接后果**：

1. **不能不加深度限制**。7254 层若按每层 20px 渲染，图高 145,000px —— 完全不可用。`--max-depth` 不是可选优化，是**必需功能**。
2. **合并（同层同名聚合）无法解决递归**。`ackermann@2` 的父节点是 `ackermann@1`，`ackermann@3` 的父节点是 `ackermann@2` —— 每一层都是不同节点，**合并只能在同父同名的兄弟之间生效**，对递归链无效。只有限深能解决。
3. **限深时不能简单"截断丢弃"**，否则父节点的宽度会小于子节点之和，布局出现空洞（与 `(self)` 伪节点同一类问题）。正确做法是：
   - 超过 `--max-depth` 的部分**合并成一个合成节点**（如 `(…共 N 层递归)` 或 `(deeper)`），把值累加进去
   - 这样保证"父节点宽度 = 子节点宽度之和"的不变量

**另外**：不能假定"行数 ≈ 文件大小 / 100"。这里 79 行 = 5.5MB。解析器要用**流式逐行**读取，避免把整个文件读进内存后按行切割（或至少不要假定行长有上限）。

### 发现 4：符号还原不完美 —— 下划线被双写

| 实际输出 | 应该是 |
| --- | --- |
| `____moonbit__main` | `_moonbit_main` |
| `mizchi::bench::mandel__point` | `mizchi::bench::mandel_point` |
| `mizchi::bench::ackermann` | ✅ 正确（名字里没下划线） |

**规律**：`::` 包分隔符还原正确，但**字面下划线被编码成 `__` 且 demangler 没有折叠回 `_`**。

→ 渲染器可以加一个可选的显示后处理：把 `__` 折叠成 `_`。但要注意这可能误伤真实含双下划线的名字，建议做成 `--undouble` 开关并在 README 说明。

### 发现 5：根帧名是空的 / 是 mangled 名

- 一部分栈以 **空帧名开头**（`;ackermann;...` 或 `:ackermann...`）
- 另一部分以 `____moonbit__main` 开头

→ 渲染器必须能处理**空帧名**（不能崩溃、不能渲染成没有标签的怪框），并对根节点做兜底命名（如 `(root)`）。

---

## 6. 对项目设计的影响（必须更新设计文档）

| 原设计 | 需要改成 |
| --- | --- |
| `--max-depth` 默认 12（可选） | **默认开启**（建议 32–64），且**超深部分合并为合成节点**而非丢弃 |
| "1 万行约 400KB，可接受" | 改为"**79 行可能是 5.5MB**"——按字节和深度双重设限 |
| 值当整数采样计数 | 当**浮点权重**，附 `--unit` 标注（ns/µs/ms/count） |
| 帧名直接渲染 | 增加可选 `__` → `_` 折叠；根节点空名兜底 |
| 合并策略：同层同名合并 | 保留，但要**明确它不能折叠递归链**，必须搭配限深 |

---

## 7. 环境踩坑记录（对你后续开发有用）

| 问题 | 现象 | 解决 |
| --- | --- | --- |
| **Schannel 被沙箱阻断** | cargo / curl / PowerShell 全部报 `SEC_E_NO_CREDENTIALS`，node 却正常 | 放宽文件沙箱权限后恢复。根因是 Schannel 需要访问凭证存储 |
| **crates.io 下载卡死** | `transfer too slow: failed to transfer more than 10 bytes in 30s` | 首次下载完成后改用 `--offline` 编译；或配置 crates 镜像 / Clash 代理（`127.0.0.1:7897`） |
| **本机没有 MSVC** | 只有 MinGW gcc 15.2.0（`E:\mingw64`） | 必须用 `x86_64-pc-windows-gnu` 工具链 |
| **没有预编译二进制** | GitHub releases 只有 v0.1.1 且 0 assets；npm 无包 | 只能从源码编译（有缓存后约 7 分钟） |
| **`cargo install` 用临时目录** | 中途中断则编译进度全丢 | 必须设置 `CARGO_TARGET_DIR` 到持久目录，才能断点续编 |

---

## 8. 最终建议

**路径二成立，应该作为主数据链路。** 建议的最终架构：

```text
【数据源 A：真实采样，主 demo】
  MoonBit wasm-gc 程序
    → moon-pprof profile --wasm-gc      (Rust，仅采集端需要)
    → .pb.gz → pprof2folded → folded
                                    ╲
【数据源 B：自带插桩，兜底/跨平台】     ╲
  用户程序 + PhaseRecorder → folded   →  moonflame（纯 MoonBit，零依赖）
                                          → flame.svg
```

**理由**：
1. 路径二产出的**符号是可读的**，绕开了 native 的符号混淆问题；
2. 链路**不改被测程序一行代码**，演示最有说服力；
3. 两条路径**产出同一格式**，渲染器只认 folded，互不干扰 —— 这反过来证明折叠栈作为内部格式的选择是对的。

**必须写进 README 的三条限制**：
1. 采样只支持 **wasm / wasm-gc** 目标（native CLI 无法采样）；
2. 需要 Rust 工具链（**仅采集端**；渲染器本身零依赖）；
3. 真实递归程序会产生极深栈，图中超过 `--max-depth` 的部分会被合并显示。

---

## 9. 自建 MoonBit 程序实测（补充验证）

前面各节用的是 moon-pprof 仓库里**预编译好的样例 wasm**。为确认「自己写的 MoonBit 程序能否走完整条链路」，在 `demo/` 下写了一个演示负载（4 个阶段：排序 / 字符串 / 矩阵 / 递归），编译成 wasm-gc 后采样。

### 9.1 结论：全链路可用 ✅

```bash
moon build --target wasm-gc
moon-pprof profile --wasm-gc _build/wasm-gc/debug/build/cmd/main/main.wasm \
    --iterations 3 --out demo.pb.gz
moon-pprof pprof2folded demo.pb.gz demo.folded
```

- 自建 wasm-gc 二进制被正常加载、执行、采样；
- 同一负载的 **wasm 与 native 运行结果完全一致**（checksum `10118596`），说明采样没有改变程序行为；
- **符号可读**：`moonflame::demo::build__strings`、`moonflame::demo::bubble__sort`、`array::Array::at`、`string::StringView::contains` 等；
- 一键复现脚本：`demo/reproduce.ps1`。

### 9.2 产物形状良好 ✅

`testdata/demo.folded`（自建 demo 数据）：

| 指标 | 值 |
| --- | --- |
| 栈数 / 不同栈 | 32 / 32 |
| 不同帧名 | 24 |
| 栈深度 | **3 ~ 28**（中位 6） |
| 总权重 | 888 ms |

对比 `testdata/stress-recursive.folded` 的 7254 层——这份 demo 数据是"可读的形状"：3 层深的主干 + 清晰的并列分支 + `fib` 递归形成的窄深尖峰。

### 9.3 ⚠️ 重要发现：采样密度由「函数调用频率」决定，不是运行时长

这是本轮最有价值的发现。

| 负载类型 | 样本数 | 时长 | 采样密度 |
| --- | --- | --- | --- |
| **递归主导**（调用密集） | 55 | 91.89 ms | **599 样本/秒** |
| **循环密集**（紧内循环） | ~40 | 963 ms | **42 样本/秒** |

**相差 14 倍。** 而且：

- `--interval-us` 从 1000 改到 100：样本数 38 → 52 → 48（**几乎无变化**）；
- `--iterations` 从 1 增到 10：运行时 488ms → 8440ms（**涨 17 倍**），样本数 36 → 59（**只涨 1.6 倍**）。

**机制解释**：wasmtime 的 epoch 中断发生在 guest 的**函数入口**等检查点上，所以采样机会正比于「经过函数边界的次数」，而不是墙钟时间。每个样本携带"距上次采样经过的时间"，因此**总时间归属是正确的**，但**分辨率很粗**：

- 调用密集时约 **1.7 ms**
- 循环密集时约 **24 ms**

**含义（必须写进 README 的限制）**：

1. **循环密集的程序会被严重欠采样**——而这恰恰是最常见的一类性能热点；
2. 任何**短于分辨率**（约 25ms）的函数可能**完全采不到**；
3. demo 数据的每个阶段应保证 **≥100 ms**，否则比例不可靠；
4. **不要指望"跑久一点"能提高统计质量**——样本数几乎不随时长增长。

### 9.4 ⚠️ 符号还原不完整（与第 5 节发现相互印证）

同一份数据里两类名字并存：

| 帧名 | 状态 |
| --- | --- |
| `moonflame::demo::bubble__sort` | ✅ 已还原（`::` 分隔） |
| `moonflame::demo::build__strings` | ✅ 已还原 |
| `moonflame4demo13run__workload` | ❌ **仍是 mangled**（`4demo` = 长度前缀） |
| `moonflame4demo13scan__strings` | ❌ **仍是 mangled** |

→ **渲染器不能假设所有帧名都已被还原**。建议：至少不因名字异常而崩溃；可选提供 `--undouble`（`__` → `_`）与 `--demangle-len`（还原 `pkgNname` 形式）两个后处理开关，并在 README 说明这是上游符号还原不完整所致。

### 9.5 对 demo 数据设计的影响

- demo 负载要**保证每个阶段 ≥100ms**（本次为 100–450ms，满足）；
- **适当增加函数调用层次**可提高分辨率，但要避免深递归（本次 `fib(32)` 约 29 层，安全）；
- 数据来源与复现方式必须写进 README：**"由 `demo/` 目录下的程序真实采样得到，可按 `demo/reproduce.ps1` 一键复现"**——这直接对应验收要求的"可复现的演示说明"。

### 9.6 `testdata/demo.folded` 的来源与「冻结」

这份文件是**跑完整条链路后的一次采样结果被固化下来的副本**，不是手工构造的：

```text
demo/demo.mbt ──moon build --target wasm-gc──▶ demo/_build/.../main.wasm
             ──moon-pprof profile --iterations 3──▶ demo.pb.gz
             ──moon-pprof pprof2folded──▶ demo.folded ──复制──▶ testdata/demo.folded
```

**为什么要冻结而不是每次现采？**

1. `moon-pprof` 只在**采集端**需要，且要从源码编译（44.6MB，见第 2 节），仓库不打包它——
   评委拿到仓库后不该被迫先装 Rust 才能看到图；
2. `examples/flame.svg` 与 README 里引用的行数/耗时，都**以这一份为准**；
3. 回归测试的行是从**这一份**里摘录的——文件变了，摘录就失去了参照。

**采样是随机的，所以每次重跑都会得到不同的一份。** 实测同一份负载、同一套命令：

| | 提交的 `testdata/demo.folded` | 重跑一次得到的 |
| --- | --- | --- |
| 栈数 | 32 | 34 |
| 栈深度 | 3 – 28 | 3 – 27 |
| 总权重 | 888 ms | 897.9 ms |
| `pprof2folded` 报告的原始样本数 | — | 61 |

热点**排序**在各次之间是稳定的（`build__strings` 始终第一），但绝对数值与栈数会浮动。
因此任何**硬编码总耗时或栈数**的断言都不应针对现采数据，只能针对冻结的这份。

**注意**：测试**不读取**这些文件。`folded_realdata_test.mbt` / `calltree_test.mbt` / `hotspot_test.mbt`
只是把文件里的若干行**内嵌**为字面量（已核对，权重 `3009200` / `5707200` / `35055400` 均逐字命中），
因此 `testdata/` 是给人和评委看的资产，不是测试的运行时依赖。

---

## 10. 留存的可复现资产

| 路径 | 说明 |
| --- | --- |
| `demo/` | 演示负载的 MoonBit 源码（4 个阶段），可直接复现数据 |
| `demo/reproduce.ps1` | 一键复现脚本：编译 → 采样 → 转折叠栈 |
| `testdata/demo.wasm` / `demo.pb.gz` | 自建 demo 的 wasm-gc 二进制与采样结果 |
| **`testdata/demo.folded`** | ⭐ **主 demo 数据**：32 栈 / 深度 3–28 / 888 ms。
| `testdata/official-sample.wasm` / `.pb.gz` | moon-pprof 官方样例（Apache-2.0），保留来源 |
| **`testdata/stress-recursive.folded`** | ⭐ **极限用例**：79 栈 / 最深 7254 层 / 5.5 MB，用于测试限深与合并 |
| `tools/analyze_folded.js` | 折叠栈分析脚本（深度分布、Top-N、帧名统计） |
| `tools/check_topic.js` | 选题撞车自查工具 |
