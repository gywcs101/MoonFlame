///|
/// 黑盒测试：命令行参数解析。
///
/// 参数解析被刻意拆成独立包，就是为了能在这里脱离文件系统单独测试。

///|
fn config_of(argv : Array[String]) -> @cli.Config raise {
  @cli.parse_config(argv)
}

///|
test "applies defaults when only the input is given" {
  let config = config_of(["demo.folded"])
  assert_eq(config.input, "demo.folded")
  assert_true(config.out is None)
  assert_true(config.top is None)
  assert_eq(config.max_depth, @cli.DEFAULT_MAX_DEPTH)
  assert_eq(config.width, @cli.DEFAULT_WIDTH)
  assert_false(config.inverted)
}

///|
test "reads the output path" {
  let config = config_of(["demo.folded", "--out", "flame.svg"])
  guard config.out is Some(path) else { fail("expected an output path") }
  assert_eq(path, "flame.svg")
}

///|
test "reads the short output flag" {
  let config = config_of(["demo.folded", "-o", "flame.svg"])
  guard config.out is Some(path) else { fail("expected an output path") }
  assert_eq(path, "flame.svg")
}

///|
test "reads the depth limit" {
  let config = config_of(["demo.folded", "--max-depth", "8"])
  assert_eq(config.max_depth, 8)
}

///|
test "accepts an unlimited depth of zero" {
  // 0 表示不限深，用于观察完整调用栈
  let config = config_of(["demo.folded", "--max-depth", "0"])
  assert_eq(config.max_depth, 0)
}

///|
test "reads the top-N request" {
  let config = config_of(["demo.folded", "--top", "10"])
  guard config.top is Some(count) else { fail("expected a top count") }
  assert_eq(count, 10)
}

///|
test "reads the canvas width" {
  let config = config_of(["demo.folded", "--width", "900"])
  assert_eq(config.width, 900.0)
}

///|
test "reads the inverted flag" {
  assert_true(config_of(["demo.folded", "--inverted"]).inverted)
  assert_false(config_of(["demo.folded"]).inverted)
}

///|
test "falls back to defaults on an unparsable number" {
  let config = config_of([
    "demo.folded", "--max-depth", "abc", "--width", "wide",
  ])
  assert_eq(config.max_depth, @cli.DEFAULT_MAX_DEPTH)
  assert_eq(config.width, @cli.DEFAULT_WIDTH)
}

///|
test "fails when the input file is missing" {
  let outcome : Result[@cli.Config, Error] = Ok(@cli.parse_config([])) catch {
    error => Err(error)
  }
  assert_true(outcome is Err(_))
}

///|
test "exposes help text for the CLI" {
  let help = @cli.command().render_help()
  assert_true(help.contains("moonflame"))
  assert_true(help.contains("max-depth"))
  assert_true(help.contains("inverted"))
}
