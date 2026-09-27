///|
/// 黑盒测试：权重单位的解析与格式化。
///
/// 折叠栈的权重是不透明的——`moon-pprof` 给纳秒，`perf` 给采样计数，
/// 数值本身区分不出来，所以单位必须显式声明，显示方式随之变化。

///|
test "parses the accepted spellings" {
  // 用 assert_true 而非 assert_eq：assert_eq 依赖已废弃的 Show trait，
  // 在 `moon test --deny-warn` 下会让 CI 变红
  for text in ["ns", "nanoseconds", "Nanosecond"] {
    assert_true(
      @moonflame.WeightUnit::parse(text) == Some(@moonflame.Nanoseconds),
    )
  }
  for text in ["us", "µs", "microseconds"] {
    assert_true(
      @moonflame.WeightUnit::parse(text) == Some(@moonflame.Microseconds),
    )
  }
  for text in ["ms", "milliseconds", "Millisecond"] {
    assert_true(
      @moonflame.WeightUnit::parse(text) == Some(@moonflame.Milliseconds),
    )
  }
  for text in ["s", "sec", "seconds"] {
    assert_true(@moonflame.WeightUnit::parse(text) == Some(@moonflame.Seconds))
  }
  for text in ["count", "counts", "samples", "sample"] {
    assert_true(@moonflame.WeightUnit::parse(text) == Some(@moonflame.Count))
  }
}

///|
test "rejects unknown spellings" {
  for text in ["", "furlongs", "nsec", "minute", "42"] {
    assert_true(@moonflame.WeightUnit::parse(text) is None)
  }
}

///|
test "labels round-trip through parse" {
  for
    unit in [
      @moonflame.Count,
      @moonflame.Nanoseconds,
      @moonflame.Microseconds,
      @moonflame.Milliseconds,
      @moonflame.Seconds,
    ] {
    assert_true(@moonflame.WeightUnit::parse(unit.label()) == Some(unit))
  }
}

///|
test "scales durations to a readable magnitude" {
  // 与 go tool pprof 的做法一致：按数量级自动选择单位
  assert_eq(@moonflame.format_weight(999.0, @moonflame.Nanoseconds), "999 ns")
  assert_eq(@moonflame.format_weight(1000.0, @moonflame.Nanoseconds), "1 µs")
  assert_eq(@moonflame.format_weight(1500.0, @moonflame.Nanoseconds), "1.5 µs")
  assert_eq(
    @moonflame.format_weight(871808200.0, @moonflame.Nanoseconds),
    "871.81 ms",
  )
  assert_eq(
    @moonflame.format_weight(2500000000.0, @moonflame.Nanoseconds),
    "2.5 s",
  )
}

///|
test "honours the declared source unit" {
  // 同一串数字，声明成不同单位必须得到不同结果
  assert_eq(@moonflame.format_weight(5.0, @moonflame.Nanoseconds), "5 ns")
  assert_eq(@moonflame.format_weight(5.0, @moonflame.Microseconds), "5 µs")
  assert_eq(@moonflame.format_weight(5.0, @moonflame.Milliseconds), "5 ms")
  assert_eq(@moonflame.format_weight(5.0, @moonflame.Seconds), "5 s")
}

///|
test "shows counts as grouped integers without a unit suffix" {
  // 加单位后缀会让人误以为它是时间，所以计数不加
  assert_eq(@moonflame.format_weight(42.0, @moonflame.Count), "42")
  assert_eq(@moonflame.format_weight(1234567.0, @moonflame.Count), "1,234,567")
  assert_eq(@moonflame.format_weight(1000.0, @moonflame.Count), "1,000")
  assert_eq(@moonflame.format_weight(999.0, @moonflame.Count), "999")
}

///|
test "handles negative values without losing the sign" {
  // 差异模式下会出现负权重
  assert_eq(
    @moonflame.format_weight(-1500000.0, @moonflame.Nanoseconds),
    "-1.5 ms",
  )
  assert_eq(
    @moonflame.format_weight(-1234567.0, @moonflame.Count),
    "-1,234,567",
  )
  assert_eq(
    @moonflame.format_signed_weights(-1500000.0, @moonflame.Nanoseconds),
    "-1.5 ms",
  )
}

///|
test "marks growth with an explicit plus sign" {
  assert_eq(
    @moonflame.format_signed_weights(1500000.0, @moonflame.Nanoseconds),
    "+1.5 ms",
  )
  assert_eq(@moonflame.format_signed_weights(250.0, @moonflame.Count), "+250")
  // 零不带符号
  assert_eq(@moonflame.format_signed_weights(0.0, @moonflame.Count), "0")
}

///|
test "formats deterministically" {
  for value in [0.0, 1.0, 999.0, 1000.0, 1234567.0, -1234567.0, 871808200.0] {
    assert_eq(
      @moonflame.format_weight(value, @moonflame.Nanoseconds),
      @moonflame.format_weight(value, @moonflame.Nanoseconds),
    )
  }
}
