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
/// 写文件；失败时打印原因并返回 `false`。
fn write_file(path : String, text : String) -> Bool {
  let outcome : Result[Unit, @fs.IOError] = Ok(
    @fs.write_string_to_file(path, text),
  ) catch {
    error => Err(error)
  }
  match outcome {
    Ok(_) => true
    Err(@fs.IOError(message)) => {
      println("moonflame: \{message}")
      false
    }
  }
}

///|
/// 输出结果：给了 `--out` 就写文件，否则打到标准输出。
fn emit(config : @cli.Config, text : String, what : String) -> Unit {
  match config.out {
    Some(path) =>
      if write_file(path, text) {
        println("moonflame: wrote \{path} (\{what})")
      }
    // 不给 --out 时打到标准输出
    None => println(text)
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
/// 读两份剖面并做差异标注（宽度按第二份走）。
fn diffed_trees(
  config : @cli.Config,
) -> (@moonflame.CallTree, @moonflame.CallTree)? {
  let after = match tree_of_file(config.input, config.max_depth) {
    Some(value) => value
    None => return None
  }
  let before_path = match config.second {
    Some(path) => path
    None => {
      println("moonflame: this subcommand needs a baseline profile")
      return None
    }
  }
  let before = match tree_of_file(before_path, config.max_depth) {
    Some(value) => value
    None => return None
  }
  Some((before, after))
}

///|
/// 把调用树渲染成 SVG 并输出。
fn render_picture(config : @cli.Config, tree : @moonflame.CallTree) -> Unit {
  // `--width` 指的是最终画布宽度，左右留白由渲染层占用，
  // 因此交给布局的是扣掉留白后的内容宽度。
  let content_width = config.width - 2.0 * @moonflame.CANVAS_XPAD
  let layout = @moonflame.layout(
    tree,
    content_width,
    @moonflame.FRAME_HEIGHT,
    inverted=config.inverted,
  )
  let svg = @moonflame.render_svg(layout, unit=config.unit)
  emit(
    config,
    svg,
    "\{layout.rects.length()} rects, \{layout.row_count()} rows",
  )
}

///|
/// 按动作分发。IO 失败就地报错并返回，不让异常穿透到顶层。
fn run(config : @cli.Config) -> Unit {
  match config.action {
    @cli.Render => {
      let tree = match tree_of_file(config.input, config.max_depth) {
        Some(value) => value
        None => return
      }
      render_picture(config, tree)
    }
    @cli.Diff => {
      let (before, after) = match diffed_trees(config) {
        Some(pair) => pair
        None => return
      }
      // 差异模式：拿基线给当前树的每个节点标注变化量。
      // 宽度仍按当前剖面走，所以只在基线里出现的帧不会显示。
      render_picture(config, @moonflame.diff_against(after, before))
    }
    @cli.Hotspots(count) => {
      let tree = match tree_of_file(config.input, config.max_depth) {
        Some(value) => value
        None => return
      }
      emit(
        config,
        @moonflame.render_hotspots(
          @moonflame.top_hotspots(tree, count),
          tree.total,
          config.unit,
        ),
        "hotspot report",
      )
    }
    @cli.Callers(wanted) => {
      let tree = match tree_of_file(config.input, config.max_depth) {
        Some(value) => value
        None => return
      }
      emit(
        config,
        @moonflame.render_relations(
          @moonflame.find_callers(tree, wanted),
          wanted,
          "调用者",
          config.unit,
        ),
        "caller report",
      )
    }
    @cli.Callees(wanted) => {
      let tree = match tree_of_file(config.input, config.max_depth) {
        Some(value) => value
        None => return
      }
      emit(
        config,
        @moonflame.render_relations(
          @moonflame.find_callees(tree, wanted),
          wanted,
          "被调用",
          config.unit,
        ),
        "callee report",
      )
    }
    @cli.Delta(count) => {
      let (before, after) = match diffed_trees(config) {
        Some(pair) => pair
        None => return
      }
      emit(
        config,
        @moonflame.render_delta(
          @moonflame.compute_delta(before, after, count),
          before.total,
          after.total,
          config.unit,
        ),
        "delta report",
      )
    }
    @cli.Filter(pattern) => {
      // 过滤后仍是折叠栈格式，可以直接再喂给默认命令出图
      let text = match read_file(config.input) {
        Some(value) => value
        None => return
      }
      let kept = @moonflame.filter_folded(text, pattern)
      if kept == "" {
        println("moonflame: no stack contains 「\{pattern}」")
        return
      }
      emit(config, kept, "filtered folded stacks")
    }
  }
}
