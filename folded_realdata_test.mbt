///|
/// 回归测试：锁定**真实采样数据**中的帧名形状。
///
/// 下面用例的输入摘自 `testdata/` 中的真实数据（由 moon-pprof 采样得到），
/// 不是构造出来的。上游的符号还原并不完整，因此帧名同时存在多种形态：
///
/// | 形态 | 真实例子 |
/// | --- | --- |
/// | 已还原（`::` 分隔） | `moonflame::demo::bubble__sort` |
/// | 未还原（长度前缀） | `moonflame4demo13run__workload` |
/// | 部分还原 | `array5Array3set` |
/// | 点号分隔 | `moonbit.add_string` |
///
/// 解析器必须**原样保留**这些名字，不做任何猜测性「修正」：
/// `__` → `_` 之类的显示归一化属于渲染层的可选开关，不能混进解析层。

///|
test "preserves every naming style verbatim" {
  let line = "____moonbit__main;moonflame4demo13run__workload;array5Array3set;moonbit.add_string 1"
  let sample = @moonflame.parse_line(line)
  guard sample is Some(s) else { fail("expected a sample") }
  assert_true(
    s.frames ==
    [
      "____moonbit__main", "moonflame4demo13run__workload", "array5Array3set", "moonbit.add_string",
    ],
  )
}

///|
test "does not apply the placeholder to ugly but non-empty names" {
  // `____moonbit__main` 是真实数据里的根帧名：虽丑但非空，必须原样保留。
  // 兜底只针对**空**帧名。
  let sample = @moonflame.parse_line(
    "____moonbit__main;moonflame::demo::fib 100",
  )
  guard sample is Some(s) else { fail("expected a sample") }
  assert_eq(s.frames[0], "____moonbit__main")
}

///|
test "parses real lines from testdata/demo.folded" {
  let text = "____moonbit__main;moonflame4demo13run__workload;moonflame::demo::matmul 3009200\n" +
    "____moonbit__main;moonflame4demo13run__workload;moonflame::demo::matmul;array::Array::at 5707200\n" +
    "____moonbit__main;moonflame4demo13run__workload;moonflame::demo::bench__sorting;moonflame::demo::bubble__sort 35055400\n"
  let result = @moonflame.parse_folded(text)
  assert_eq(result.samples.length(), 3)
  assert_eq(result.skipped_lines, 0)
  assert_eq(result.samples[2].frames.length(), 4)
  assert_eq(result.samples[2].frames[3], "moonflame::demo::bubble__sort")
  assert_eq(result.samples[2].weight, 35055400.0)
}

///|
test "parses the deepest and longest line shape found in the real data" {
  // testdata/stress-recursive.folded 中最深的一行：
  // 根帧 `____moonbit__main` + 7253 层 `mizchi::bench::ackermann` 递归，共 7254 层。
  // 栈部分 181,342 字符，整行 181,350 字符——解析器不能对深度或行长设限。
  let depth = 7254
  let recursion = Array::make(depth - 1, "mizchi::bench::ackermann").join(";")
  let stack = "____moonbit__main;" + recursion
  assert_eq(stack.length(), 181342)
  let sample = @moonflame.parse_line(stack + " 3182800")
  guard sample is Some(s) else { fail("expected a sample") }
  assert_eq(s.frames.length(), depth)
  assert_eq(s.frames[0], "____moonbit__main")
  assert_eq(s.frames[depth - 1], "mizchi::bench::ackermann")
  assert_eq(s.weight, 3182800.0)
}

///|
test "keeps large nanosecond weights exact" {
  // 上游的权重是**纳秒时间**而非采样计数，数值可达 10^8 量级，
  // 解析时不能被截断成整数计数。
  let sample = @moonflame.parse_line(
    "____moonbit__main;mizchi::bench::ackermann 887997400",
  )
  guard sample is Some(s) else { fail("expected a sample") }
  assert_eq(s.weight, 887997400.0)
}
