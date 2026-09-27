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
  assert_true(config.action is @cli.Render)
  assert_true(config.second is None)
  assert_eq(config.max_depth, @cli.DEFAULT_MAX_DEPTH)
  assert_eq(config.width, @cli.DEFAULT_WIDTH)
  assert_false(config.inverted)
  // 默认按纳秒解读权重——与本项目文档里的主链路一致
  assert_true(config.unit == @moonflame.Nanoseconds)
}

///|
test "reads the output path, long and short" {
  for
    argv in [
      ["demo.folded", "--out", "flame.svg"],
      ["demo.folded", "-o", "flame.svg"],
    ] {
    guard config_of(argv) is { out: Some(path), .. } else {
      fail("expected an output path")
    }
    assert_eq(path, "flame.svg")
  }
}

///|
test "reads the depth limit and accepts an unlimited zero" {
  assert_eq(config_of(["demo.folded", "--max-depth", "8"]).max_depth, 8)
  // 0 表示不限深，用于观察完整调用栈
  assert_eq(config_of(["demo.folded", "--max-depth", "0"]).max_depth, 0)
}

///|
test "reads the canvas width" {
  assert_eq(config_of(["demo.folded", "--width", "900"]).width, 900.0)
}

///|
test "reads the weight unit" {
  assert_true(
    config_of(["demo.folded", "--unit", "ms"]).unit == @moonflame.Milliseconds,
  )
  assert_true(
    config_of(["demo.folded", "--unit", "count"]).unit == @moonflame.Count,
  )
  assert_true(
    config_of(["demo.folded", "--unit", "us"]).unit == @moonflame.Microseconds,
  )
}

///|
test "falls back to nanoseconds on an unknown unit" {
  assert_true(
    config_of(["demo.folded", "--unit", "furlongs"]).unit ==
    @moonflame.Nanoseconds,
  )
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
test "exposes help text listing every subcommand" {
  let help = @cli.command().render_help()
  assert_true(help.contains("moonflame"))
  assert_true(help.contains("max-depth"))
  assert_true(help.contains("unit"))
  assert_true(help.contains("inverted"))
  for name in ["diff", "delta", "hotspots", "callers", "callees", "filter"] {
    assert_true(help.contains(name))
  }
}

///|
test "the top-level command carries no report options" {
  // 报告类功能都在子命令里，顶层只负责出图——这是参数不膨胀的关键
  let help = @cli.command().render_help()
  assert_true(!help.contains("--top"))
}

///|
test "parses the diff subcommand" {
  let config = config_of([
    "diff", "before.folded", "after.folded", "-o", "diff.svg",
  ])
  assert_true(config.action is @cli.Diff)
  guard config.second is Some(before) else { fail("expected a baseline") }
  assert_eq(before, "before.folded")
  // 宽度按当前剖面走，因此 input 是「之后」的那份
  assert_eq(config.input, "after.folded")
  guard config.out is Some(path) else { fail("expected an output path") }
  assert_eq(path, "diff.svg")
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
    "--unit", "us",
  ])
  assert_eq(config.max_depth, 4)
  assert_eq(config.width, 900.0)
  assert_true(config.inverted)
  assert_true(config.unit == @moonflame.Microseconds)
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

///|
test "parses the hotspots subcommand" {
  let config = config_of(["hotspots", "demo.folded", "--top", "5"])
  assert_true(config.action is @cli.Hotspots(5))
  assert_eq(config.input, "demo.folded")
  assert_true(config.out is None)
}

///|
test "hotspots defaults to the standard count" {
  let config = config_of(["hotspots", "demo.folded"])
  assert_true(config.action is @cli.Hotspots(@cli.DEFAULT_TOP))
}

///|
test "parses the callers and callees subcommands" {
  let callers = config_of(["callers", "demo.folded", "build_strings"])
  assert_true(callers.action is @cli.Callers("build_strings"))
  assert_eq(callers.input, "demo.folded")
  let callees = config_of(["callees", "demo.folded", "walk_tree"])
  assert_true(callees.action is @cli.Callees("walk_tree"))
  assert_eq(callees.input, "demo.folded")
}

///|
test "call queries need both a file and a name" {
  for argv in [["callers", "demo.folded"], ["callees"]] {
    let outcome : Result[@cli.Config, Error] = Ok(@cli.parse_config(argv)) catch {
      error => Err(error)
    }
    assert_true(outcome is Err(_))
  }
}

///|
test "parses the delta subcommand" {
  let config = config_of(["delta", "b.folded", "a.folded", "--top", "3"])
  assert_true(config.action is @cli.Delta(3))
  assert_eq(config.input, "a.folded")
  guard config.second is Some(before) else { fail("expected a baseline") }
  assert_eq(before, "b.folded")
}

///|
test "delta defaults to the standard count" {
  let config = config_of(["delta", "b.folded", "a.folded"])
  assert_true(config.action is @cli.Delta(@cli.DEFAULT_TOP))
}

///|
test "parses the filter subcommand" {
  let config = config_of([
    "filter", "build_strings", "demo.folded", "-o", "sub.folded",
  ])
  assert_true(config.action is @cli.Filter("build_strings"))
  assert_eq(config.input, "demo.folded")
  guard config.out is Some(path) else { fail("expected an output path") }
  assert_eq(path, "sub.folded")
}

///|
test "rejects an unknown subcommand" {
  let outcome : Result[@cli.Config, Error] = Ok(
    @cli.parse_config(["nonsense", "demo.folded"]),
  ) catch {
    error => Err(error)
  }
  assert_true(outcome is Err(_))
}
