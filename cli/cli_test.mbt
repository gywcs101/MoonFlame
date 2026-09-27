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

///|
test "render mode carries no baseline" {
  assert_true(config_of(["demo.folded"]).baseline is None)
}

///|
test "parses the diff subcommand" {
  let config = config_of([
    "diff", "before.folded", "after.folded", "-o", "diff.svg",
  ])
  guard config.baseline is Some(before) else { fail("expected a baseline") }
  assert_eq(before, "before.folded")
  // 宽度按当前剖面走，因此 input 是「之后」的那份
  assert_eq(config.input, "after.folded")
  guard config.out is Some(path) else { fail("expected an output path") }
  assert_eq(path, "diff.svg")
  // 差异模式不打印热点榜
  assert_true(config.top is None)
}

///|
test "diff subcommand applies the same draw defaults" {
  let config = config_of(["diff", "b.folded", "a.folded"])
  assert_eq(config.max_depth, @cli.DEFAULT_MAX_DEPTH)
  assert_eq(config.width, @cli.DEFAULT_WIDTH)
  assert_false(config.inverted)
  assert_true(config.out is None)
}

///|
test "diff subcommand accepts draw options" {
  let config = config_of([
    "diff", "b.folded", "a.folded", "--max-depth", "4", "--width", "900", "--inverted",
  ])
  assert_eq(config.max_depth, 4)
  assert_eq(config.width, 900.0)
  assert_true(config.inverted)
}

///|
test "diff subcommand needs both profiles" {
  let outcome : Result[@cli.Config, Error] = Ok(
    @cli.parse_config(["diff", "only.folded"]),
  ) catch {
    error => Err(error)
  }
  assert_true(outcome is Err(_))
}
