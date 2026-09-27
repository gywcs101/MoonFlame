///|
/// 黑盒测试：折叠栈解析。
///
/// 覆盖解析器对外契约：正常行、权重格式、空帧名兜底、异常输入与规模上限。

///|
test "parses a plain line" {
  let sample = @moonflame.parse_line("main;compute;fft 900")
  guard sample is Some(s) else { fail("expected a sample") }
  assert_true(s.frames == ["main", "compute", "fft"])
  assert_eq(s.weight, 900.0)
}

///|
test "parses an integer weight and a decimal weight" {
  let integer = @moonflame.parse_line("main 100")
  guard integer is Some(a) else { fail("expected a sample") }
  assert_eq(a.weight, 100.0)
  let decimal = @moonflame.parse_line("main 1395.5")
  guard decimal is Some(b) else { fail("expected a sample") }
  assert_eq(b.weight, 1395.5)
}

///|
test "replaces an empty root frame with a placeholder" {
  // 真实采样数据里出现过以空帧开头的栈，例如 ":ackermann;..."
  let sample = @moonflame.parse_line(";ackermann;fib 10")
  guard sample is Some(s) else { fail("expected a sample") }
  assert_true(s.frames == ["(root)", "ackermann", "fib"])
}

///|
test "replaces every empty frame, not just the root" {
  let sample = @moonflame.parse_line("a;;b; 5")
  guard sample is Some(s) else { fail("expected a sample") }
  assert_true(s.frames == ["a", "(root)", "b", "(root)"])
}

///|
test "keeps spaces inside a frame name" {
  // 只有最后一个空格分隔权重，帧名内部的空格必须保留
  let sample = @moonflame.parse_line("my fn;other fn 42")
  guard sample is Some(s) else { fail("expected a sample") }
  assert_true(s.frames == ["my fn", "other fn"])
  assert_eq(s.weight, 42.0)
}

///|
test "trims surrounding whitespace and tolerates CRLF" {
  let sample = @moonflame.parse_line("  main;fft 900\r")
  guard sample is Some(s) else { fail("expected a sample") }
  assert_true(s.frames == ["main", "fft"])
  assert_eq(s.weight, 900.0)
}

///|
test "tolerates repeated spaces before the weight" {
  let sample = @moonflame.parse_line("main;fft   900")
  guard sample is Some(s) else { fail("expected a sample") }
  assert_true(s.frames == ["main", "fft"])
  assert_eq(s.weight, 900.0)
}

///|
test "rejects a line without a weight" {
  assert_true(@moonflame.parse_line("main;fft") is None)
}

///|
test "rejects a non-numeric weight" {
  assert_true(@moonflame.parse_line("main;fft abc") is None)
}

///|
test "rejects non-finite weights" {
  // NaN / Inf 会让后续布局的比例计算整体失效，必须在入口拦掉
  assert_true(@moonflame.parse_line("main;fft nan") is None)
  assert_true(@moonflame.parse_line("main;fft inf") is None)
}

///|
test "rejects blank lines" {
  assert_true(@moonflame.parse_line("") is None)
  assert_true(@moonflame.parse_line("   ") is None)
}

///|
test "handles a deeply nested stack" {
  // 真实采样数据中栈可深达数千层，解析器不能对深度设限
  let depth = 5000
  let stack = Array::make(depth, "f").join(";")
  let sample = @moonflame.parse_line(stack + " 1")
  guard sample is Some(s) else { fail("expected a sample") }
  assert_eq(s.frames.length(), depth)
  assert_eq(s.frames[0], "f")
  assert_eq(s.frames[depth - 1], "f")
}

///|
test "parse_folded counts skipped lines but ignores blank ones" {
  let text = "a;b 1\n\nc;d 2\nbroken line\nnospace\n   \ne;f 3\n"
  let result = @moonflame.parse_folded(text)
  assert_eq(result.samples.length(), 3)
  assert_eq(result.skipped_lines, 2)
}

///|
test "parse_folded keeps samples in input order" {
  let result = @moonflame.parse_folded("a 1\nb 2\nc 3")
  let weights = result.samples.map(fn(s) { s.weight })
  assert_true(weights == [1.0, 2.0, 3.0])
}

///|
test "parse_folded on empty input yields nothing" {
  let result = @moonflame.parse_folded("")
  assert_eq(result.samples.length(), 0)
  assert_eq(result.skipped_lines, 0)
}
