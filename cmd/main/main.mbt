///|
/// MoonFlame 命令行入口。
///
/// 只做三件事：读文件、调用核心库、写结果。所有实际逻辑都在根包里，
/// 这里刻意保持"薄"，方便核心库在没有文件系统的环境里复用。
///
/// 文件读写用 `moonbitlang/x/fs`：核心库没有 IO，而官方另一个并发运行时
/// `moonbitlang/async` 在 Windows 上只支持 MSVC，MinGW 环境无法构建。

///|
fn main {
  let argv = @env.args()
  let config = @cli.parse_config(argv[1:]) catch {
    _ => {
      // 参数不合法时打印用法
      println(@cli.command().render_help())
      return
    }
  }
  run(config)
}

///|
/// 读取折叠栈、按配置产出报告或 SVG。IO 失败就地报错并返回，不让异常穿透到顶层。
fn run(config : @cli.Config) -> Unit {
  let text = @fs.read_file_to_string(config.input) catch {
    @fs.IOError(message) => {
      println("moonflame: \{message}")
      return
    }
  }
  let parsed = @moonflame.parse_folded(text)
  if parsed.skipped_lines > 0 {
    println("moonflame: skipped \{parsed.skipped_lines} unparsable line(s)")
  }
  if parsed.samples.length() == 0 {
    println("moonflame: no samples found in \{config.input}")
    return
  }
  let tree = @moonflame.aggregate(parsed.samples, max_depth=config.max_depth)
  match config.top {
    Some(count) =>
      println(
        @moonflame.render_hotspots(
          @moonflame.top_hotspots(tree, count),
          tree.total,
        ),
      )
    None => ()
  }
  match config.out {
    Some(path) => {
      let layout = @moonflame.layout(
        tree,
        config.width,
        20.0,
        inverted=config.inverted,
      )
      let svg = @moonflame.render_svg(layout)
      @fs.write_string_to_file(path, svg) catch {
        @fs.IOError(message) => println("moonflame: \{message}")
      }
      println(
        "moonflame: wrote \{path} (\{layout.rects.length()} rects, \{layout.row_count()} rows)",
      )
    }
    None => ()
  }
}
