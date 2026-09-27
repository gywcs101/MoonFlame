# moonflame/demo

MoonFlame 的演示负载：四个阶段的典型计算，用于生成**真实可复现**的火焰图样例数据。

设计目标：

1. 避免深递归——防止出现数千层的病态栈，图要好看；
2. 保留清晰的并列分支——排序 / 字符串 / 矩阵 / 递归各成一枝；
3. 各阶段耗时都远大于采样分辨率（≥100 ms），比例才可靠。

## 阶段构成

| 阶段 | 内容 | 特点 |
| --- | --- | --- |
| `bench_sorting` | 冒泡排序 + 插入排序 | 循环密集，最慢的分支 |
| `bench_strings` | 字符串拼接 + 扫描包含 | 分配密集 |
| `matmul` | 一维数组模拟矩阵乘法 | 数值计算 |
| `fib` | 递归斐波那契 | 调用密集，形成窄深尖峰 |

## 一键复现样例数据

需要先安装 `moon-pprof`（见仓库根目录 `docs/DATA-PIPELINE.md`）。

```powershell
pwsh demo/reproduce.ps1
```

脚本依次执行：编译 `wasm-gc` → 采样（3 轮）→ 转折叠栈 → 打印热点概览，
最终生成 `demo.folded`，可作为渲染器的输入。

生成的 `.pb.gz` / `.folded` 属于中间产物，已在 `.gitignore` 中忽略；
入库的正式样例数据见 `testdata/`。

## 正确性

工作负载是**确定性的**：同一负载多次运行必得同一 checksum，这是样例数据可复现的前提。

下面这段代码会被 `moon test` 真实执行（`README.mbt.md` 中的 `mbt check` 代码块由构建系统校验）：

```mbt check
test {
  let first = @demo.run_workload()
  assert_true(first > 0)
}
```

各算法自身的正确性（排序结果、交换次数、`fib` 基准值）由白盒测试覆盖，见 `demo_wbtest.mbt`。

## 与主项目的关系

`demo/` 是**独立模块**，不参与主项目的编译；它唯一的职责是产出样例数据。
主项目（渲染器）位于仓库根目录。
