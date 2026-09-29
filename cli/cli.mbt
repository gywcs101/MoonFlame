///|
/// 命令行参数解析。
///
/// 刻意与渲染逻辑分开：根包只做纯计算、不依赖任何外部包，
/// 参数解析放在这里，既让核心保持干净，也让它自己能单独测试。
///
/// **形状约定**：默认命令（不带子命令）只负责「出一张图」；一切**文本报告**
/// 都是子命令。这样顶层选项不会随功能增长而膨胀——顶层参数恒定保持在 5 个以内。

///|
/// 本次调用要做什么。
pub(all) enum Action {
  /// 默认：把输入渲染成 SVG（配合 `--out`）
  Render
  /// 差异渲染：对比两份剖面
  Diff
  /// 文本热点榜
  Hotspots(Int)
  /// 谁调用了这个函数
  Callers(String)
  /// 这个函数调用了谁
  Callees(String)
  /// 两份剖面的差异文本排行
  Delta(Int)
  /// 按正则过滤栈，输出折叠栈文本
  Filter(String)
} derive(Eq)

///|
/// 显式声明 `Eq` 的方法可被当作常规方法调用。
///
/// 新版编译器不再自动完成这个提升，不声明会报 `implicit_impl_as_method`。
pub extend Action with Eq::{not_equal, equal}

///|
/// 解析后的命令配置。
pub struct Config {
  /// 要执行的动作
  action : Action
  /// 主输入文件（差异类动作里是「之后」的那份）
  input : String
  /// 差异类动作的第二个文件（「之前」的基线）
  second : String?
  /// 输出路径；不传则只打印报告 / 只输出到标准输出
  out : String?
  /// 每个栈最多保留的帧数，`0` 表示不限制
  max_depth : Int
  /// 画布宽度（像素）
  width : Double
  /// 权重单位
  unit : @moonflame.WeightUnit
  /// 冰柱方向（根在顶部）；默认为火焰图方向（根在底部）
  inverted : Bool
} derive(Eq)

///|
/// 显式声明 `Eq` 的方法可被当作常规方法调用。
///
/// 新版编译器不再自动完成这个提升，不声明会报 `implicit_impl_as_method`。
pub extend Config with Eq::{not_equal, equal}

///|
/// 默认深度上限：真实递归栈可达数千层，不限深画出来的图没法看。
pub const DEFAULT_MAX_DEPTH : Int = 32

///|
/// 默认画布宽度。
pub const DEFAULT_WIDTH : Double = 1400.0

///|
/// 默认热点条数。
pub const DEFAULT_TOP : Int = 10

///|
/// 输出路径选项。各子命令共用。
fn out_option() -> @argparse.OptionArg {
  @argparse.OptionArg(
    "out",
    short='o',
    about="Write the output to this path (omit to print to stdout)",
  )
}

///|
fn max_depth_option() -> @argparse.OptionArg {
  @argparse.OptionArg(
    "max-depth",
    about="Keep at most N frames per stack; 0 means unlimited",
    default_values=["32"],
  )
}

///|
fn width_option() -> @argparse.OptionArg {
  @argparse.OptionArg("width", about="Canvas width in pixels", default_values=[
    "1400",
  ])
}

///|
/// 权重单位。折叠栈的第 2 列是不透明的权重，`moon-pprof` 给纳秒、
/// `perf` 给采样计数，数值本身区分不出来，因此需要声明。
fn unit_option() -> @argparse.OptionArg {
  @argparse.OptionArg(
    "unit",
    about="Unit of the weight column: ns, us, ms, s, or count",
    default_values=["ns"],
  )
}

///|
fn top_option() -> @argparse.OptionArg {
  @argparse.OptionArg("top", about="How many entries to list", default_values=[
    "10",
  ])
}

///|
/// 渲染类子命令共用的选项：只影响出图，不影响文本报告的口径。
fn render_options() -> Array[@argparse.OptionArg] {
  [out_option(), max_depth_option(), width_option(), unit_option()]
}

///|
/// 冰柱方向开关。默认是火焰图方向（根在底部）。
fn inverted_flag() -> @argparse.FlagArg {
  @argparse.FlagArg(
    "inverted",
    about="Icicle orientation: root at the top instead of the bottom",
  )
}

///|
/// 两个文件位置参数的子命令骨架，供 `diff` / `delta` 复用。
fn two_file_command(
  name : String,
  about : String,
  options : Array[@argparse.OptionArg],
  flags : Array[@argparse.FlagArg],
) -> @argparse.Command {
  @argparse.Command(name, about~, options~, flags~, positionals=[
    @argparse.PositionArg(
      "before",
      about="Baseline profile",
      num_args=@argparse.ValueRange::single(),
    ),
    @argparse.PositionArg(
      "after",
      about="Current profile",
      num_args=@argparse.ValueRange::single(),
    ),
  ])
}

///|
/// 一个文件加一个名字位置参数的子命令骨架，供 `callers` / `callees` 复用。
fn call_query_command(
  name : String,
  about : String,
  name_about : String,
) -> @argparse.Command {
  @argparse.Command(name, about~, options=[max_depth_option(), unit_option()], positionals=[
    @argparse.PositionArg(
      "input",
      about="Folded stack file",
      num_args=@argparse.ValueRange::single(),
    ),
    @argparse.PositionArg(
      "name",
      about=name_about,
      num_args=@argparse.ValueRange::single(),
    ),
  ])
}

///|
/// `diff` 子命令：对比两份剖面并出图。
///
/// 宽度按**第二个**（当前）剖面走，颜色标出相对基线是变多还是变少。
pub fn diff_command() -> @argparse.Command {
  two_file_command(
    "diff",
    "Compare two profiles: width from the current one, colour by the change",
    render_options(),
    [inverted_flag()],
  )
}

///|
/// 全部子命令。
///
/// 报告类功能一律做成子命令，顶层选项因此不会增长。
fn subcommands() -> Array[@argparse.Command] {
  [
    diff_command(),
    two_file_command(
      "delta",
      "Compare two profiles as a text ranking instead of a picture",
      [max_depth_option(), unit_option(), top_option()],
      [],
    ),
    @argparse.Command(
      "hotspots",
      about="Print the hottest functions by self time",
      options=[max_depth_option(), unit_option(), top_option()],
      positionals=[
        @argparse.PositionArg(
          "input",
          about="Folded stack file",
          num_args=@argparse.ValueRange::single(),
        ),
      ],
    ),
    call_query_command(
      "callers", "List the call paths that reach a function", "Function name to look up",
    ),
    call_query_command(
      "callees", "List what a function calls, with the time spent in each", "Function name to look up",
    ),
    @argparse.Command(
      "filter",
      about="Keep only the stacks containing a substring",
      options=[max_depth_option(), out_option()],
      positionals=[
        @argparse.PositionArg(
          "pattern",
          about="Substring matched against each stack line",
          num_args=@argparse.ValueRange::single(),
        ),
        @argparse.PositionArg(
          "input",
          about="Folded stack file",
          num_args=@argparse.ValueRange::single(),
        ),
      ],
    ),
  ]
}

///|
/// 命令行定义。顶层只有 4 个选项 + 1 个开关，报告类功能都在子命令里。
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "moonflame",
    about="Render folded stack profiles into interactive SVG flame graphs",
    version="0.1.0",
    options=render_options(),
    flags=[inverted_flag()],
    positionals=[
      // 必须允许 0 个：否则 `moonflame diff ...` 会把 "diff" 当成 input 吃掉
      @argparse.PositionArg(
        "input",
        about="Folded stack file",
        num_args=@argparse.ValueRange::ValueRange(lower=0, upper=1),
      ),
    ],
    subcommands=subcommands(),
  )
}

///|
fn int_option(
  values : Map[String, Array[String]],
  key : String,
  fallback : Int,
) -> Int {
  match values.get(key) {
    Some([text, ..]) => @string.parse_int(text) catch { _ => fallback }
    _ => fallback
  }
}

///|
fn double_option(
  values : Map[String, Array[String]],
  key : String,
  fallback : Double,
) -> Double {
  match values.get(key) {
    Some([text, ..]) => @string.parse_double(text) catch { _ => fallback }
    _ => fallback
  }
}

///|
fn text_option(values : Map[String, Array[String]], key : String) -> String? {
  match values.get(key) {
    Some([text, ..]) => Some(text)
    _ => None
  }
}

///|
/// 单位选项；无法识别的写法退回默认的纳秒。
fn unit_option_value(
  values : Map[String, Array[String]],
) -> @moonflame.WeightUnit {
  match text_option(values, "unit") {
    Some(text) =>
      match @moonflame.WeightUnit::parse(text) {
        Some(parsed) => parsed
        None => @moonflame.Nanoseconds
      }
    None => @moonflame.Nanoseconds
  }
}

///|
fn flag_of(matches : @argparse.Matches, key : String) -> Bool {
  match matches.flags.get(key) {
    Some(value) => value
    None => false
  }
}

///|
/// 从子命令的匹配结果取两个位置参数。
fn two_files(values : Map[String, Array[String]]) -> (String, String) raise {
  guard values is { "before": [before], "after": [after], .. } else {
    fail("this subcommand needs two profiles: before and after")
  }
  (before, after)
}

///|
/// 从 argv 解析配置。`argv` 不含程序名。
pub fn parse_config(argv : ArrayView[String]) -> Config raise {
  let matches = @argparse.parse(command(), argv~)
  let shared = {
    action: Render,
    input: "",
    second: None,
    out: None,
    max_depth: DEFAULT_MAX_DEPTH,
    width: DEFAULT_WIDTH,
    unit: @moonflame.Nanoseconds,
    inverted: false,
  }
  match matches.subcommand {
    Some(pair) => {
      let (name, sub) = pair
      let values = sub.values
      let base = {
        ..shared,
        out: text_option(values, "out"),
        max_depth: int_option(values, "max-depth", DEFAULT_MAX_DEPTH),
        width: double_option(values, "width", DEFAULT_WIDTH),
        unit: unit_option_value(values),
        inverted: flag_of(sub, "inverted"),
      }
      match name {
        "diff" => {
          let (before, after) = two_files(values)
          { ..base, action: Diff, input: after, second: Some(before), }
        }
        "delta" => {
          let (before, after) = two_files(values)
          {
            ..base,
            action: Delta(int_option(values, "top", DEFAULT_TOP)),
            input: after,
            second: Some(before),
          }
        }
        "hotspots" => {
          guard values is { "input": [input], .. } else {
            fail("hotspots needs a folded stack file")
          }
          {
            ..base,
            action: Hotspots(int_option(values, "top", DEFAULT_TOP)),
            input,
          }
        }
        "callers" | "callees" => {
          guard values is { "input": [input], "name": [wanted], .. } else {
            fail("\{name} needs a folded stack file and a function name")
          }
          let action = if name == "callers" {
            Callers(wanted)
          } else {
            Callees(wanted)
          }
          { ..base, action, input, }
        }
        "filter" => {
          guard values is { "pattern": [pattern], "input": [input], .. } else {
            fail("filter needs a pattern and a folded stack file")
          }
          { ..base, action: Filter(pattern), input, }
        }
        _ => fail("unknown subcommand: " + name)
      }
    }
    None => {
      let values = matches.values
      guard values is { "input": [input], .. } else {
        fail("missing input file")
      }
      {
        ..shared,
        out: text_option(values, "out"),
        max_depth: int_option(values, "max-depth", DEFAULT_MAX_DEPTH),
        width: double_option(values, "width", DEFAULT_WIDTH),
        unit: unit_option_value(values),
        inverted: flag_of(matches, "inverted"),
        input,
      }
    }
  }
}
