# moonflame/demo

MoonFlame 的 MIT 演示负载：排序、字符串、矩阵乘法和浅层分支递归。
它是独立模块，仅负责生成采样输入，不参与根模块的编译。

在仓库根目录执行 `powershell demo/reproduce.ps1` 或 `bash demo/reproduce.sh`。
需要 `moon` 与 `moon-pprof` 位于 PATH。脚本执行 wasm-gc 编译、三轮采样、
折叠栈转换和热点报告，不修改工具链，也不覆盖 `testdata/` 中的冻结数据。
采样具有随机性，各阶段耗时、采样密度和图形比例不保证固定。

负载计算结果保持确定，以下例子会被 MoonBit 测试执行：

```mbt check
///|
test {
  let checksum = @demo.run_workload()
  assert_true(checksum > 0)
}
```

在本目录运行 `moon check --deny-warn` 和 `moon test --deny-warn`。
源码和冻结样例的关系、历史版本与许可见根目录 `THIRD_PARTY_NOTICES.md`。
