///|
/// 命令行参数解析。
///
/// 刻意与渲染逻辑分开：根包只做纯计算、不依赖任何外部包，
/// 参数解析放在这里，既让核心保持干净，也让它自己能单独测试。

///|
/// 解析后的命令配置。
pub struct Config {
  /// 输入折叠栈文件
  input : String
  /// SVG 输出路径；不传则只打印报告（如有）
  out : String?
  /// 每个栈最多保留的帧数，`0` 表示不限制
  max_depth : Int
  /// 打印前 N 个热点
  top : Int?
  /// 画布宽度（像素）
  width : Double
  /// 冰柱方向（根在顶部）；默认为火焰图方向（根在底部）
  inverted : Bool
} derive(Eq)

///|
/// 默认深度上限：真实递归栈可达数千层，不限深画出来的图没法看。
pub const DEFAULT_MAX_DEPTH : Int = 32

///|
/// 默认画布宽度。
pub const DEFAULT_WIDTH : Double = 1400.0

///|
/// 命令行定义。参数刻意保持在 5 个以内，避免范围失控。
pub fn command() -> @argparse.Command {
  @argparse.Command(
    "moonflame",
    about="Render folded stack profiles into interactive SVG flame graphs",
    version="0.1.0",
    options=[
      @argparse.OptionArg(
        "out",
        short='o',
        about="Write the SVG to this path (omit to print a report only)",
      ),
      @argparse.OptionArg(
        "max-depth",
        about="Keep at most N frames per stack; 0 means unlimited",
        default_values=["32"],
      ),
      @argparse.OptionArg("top", about="Print the N hottest frames"),
      @argparse.OptionArg("width", about="Canvas width in pixels", default_values=[
        "1400",
      ]),
    ],
    flags=[
      @argparse.FlagArg(
        "inverted",
        about="Icicle orientation: root at the top instead of the bottom",
      ),
    ],
    positionals=[
      @argparse.PositionArg(
        "input",
        about="Folded stack file",
        num_args=@argparse.ValueRange::single(),
      ),
    ],
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
/// 从 argv 解析配置。`argv` 不含程序名。
pub fn parse_config(argv : ArrayView[String]) -> Config raise {
  let matches = @argparse.parse(command(), argv~)
  let values = matches.values
  guard values is { "input": [input], .. } else { fail("missing input file") }
  let top = match text_option(values, "top") {
    Some(text) => Some(@string.parse_int(text) catch { _ => 0 })
    None => None
  }
  {
    input,
    out: text_option(values, "out"),
    max_depth: int_option(values, "max-depth", DEFAULT_MAX_DEPTH),
    top,
    width: double_option(values, "width", DEFAULT_WIDTH),
    inverted: match matches.flags.get("inverted") {
      Some(value) => value
      None => false
    },
  }
}
