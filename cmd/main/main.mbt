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
/// 读文件；失败时打印原因并返回 `None`。
fn read_file(path : String) -> String? {
  let outcome : Result[String, @fs.IOError] = Ok(@fs.read_file_to_string(path)) catch {
    error => Err(error)
  }
  match outcome {
    Ok(text) => Some(text)
    Err(@fs.IOError(message)) => {
      println("moonflame: \{message}")
      None
    }
  }
}

///|
/// 解析文件并聚合成调用树。任一步失败都返回 `None`。
fn tree_of_file(path : String, max_depth : Int) -> @moonflame.CallTree? {
  let text = match read_file(path) {
    Some(value) => value
    None => return None
  }
  let parsed = @moonflame.parse_folded(text)
  if parsed.skipped_lines > 0 {
    println(
      "moonflame: skipped \{parsed.skipped_lines} unparsable line(s) in \{path}",
    )
  }
  if parsed.samples.length() == 0 {
    println("moonflame: no samples found in \{path}")
    return None
  }
  Some(@moonflame.aggregate(parsed.samples, max_depth~))
}

///|
/// 读取折叠栈、按配置产出报告或 SVG。IO 失败就地报错并返回，不让异常穿透到顶层。
fn run(config : @cli.Config) -> Unit {
  let tree = match tree_of_file(config.input, config.max_depth) {
    Some(value) => value
    None => return
  }
  // 差异模式：拿基线剖面给当前树的每个节点标注变化量。
  // 宽度仍按当前剖面走，所以只在基线里出现的帧不会显示。
  let tree = match config.baseline {
    Some(path) =>
      match tree_of_file(path, config.max_depth) {
        Some(baseline) => @moonflame.diff_against(tree, baseline)
        None => return
      }
    None => tree
  }
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
      let outcome : Result[Unit, @fs.IOError] = Ok(
        @fs.write_string_to_file(path, svg),
      ) catch {
        error => Err(error)
      }
      match outcome {
        Ok(_) =>
          println(
            "moonflame: wrote \{path} (\{layout.rects.length()} rects, \{layout.row_count()} rows)",
          )
        Err(@fs.IOError(message)) => println("moonflame: \{message}")
      }
    }
    None => ()
  }
}
