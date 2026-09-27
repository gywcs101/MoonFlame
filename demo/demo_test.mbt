// 黑盒测试：只针对公开 API。
// 这里主要验证工作负载是确定性的——它是 demo 数据可复现的前提。

///|
/// 同一负载两次运行必须得到相同结果（确定性）。
/// 注意：只断言"两次相等 + 大于 0"，不锁定具体数值，
/// 这样调整负载规模时不会误报失败。
test "run_workload 结果确定且非零" {
  let first = @demo.run_workload()
  let second = @demo.run_workload()
  assert_eq(first, second)
  assert_true(first > 0)
}
