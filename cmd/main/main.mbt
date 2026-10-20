///|
/// IO and exit status are confined to this executable package.
fn main {
  let config = @cli.parse_config(app_args()) catch {
    error => {
      eprintln("moonflame: " + error_message(error))
      @sys.exit(2)
      return
    }
  }
  let result = output(config) catch {
    error => {
      eprintln("moonflame: " + error_message(error))
      @sys.exit(1)
      return
    }
  }
  // Only open the destination after every input and computation has succeeded.
  match config.out {
    Some(path) => {
      @fs.write_string_to_file(path, result) catch {
        @fs.IOError(message) => {
          eprintln("moonflame: " + message)
          @sys.exit(1)
          return
        }
      }
      eprintln("moonflame: wrote " + path)
    }
    None => if result != "" { println(result) }
  }
}

///|
fn parsed_file(path : String) -> (String, @moonflame.ParseResult) raise {
  let text = @fs.read_file_to_string(path)
  let parsed = @moonflame.parse_folded(text)
  if parsed.skipped_lines > 0 {
    for issue in parsed.diagnostics {
      let reason = match issue.kind {
        @moonflame.MissingWeight => "missing weight"
        @moonflame.InvalidNumber => "invalid number"
        @moonflame.NonFiniteWeight => "non-finite weight"
        @moonflame.NegativeWeight => "negative weight"
      }
      eprintln("moonflame: \{path}:\{issue.line}: \{reason}")
    }
    fail("invalid profile; no output written")
  }
  (text, parsed)
}

///|
fn tree_of_file(path : String, max_depth : Int) -> @moonflame.CallTree raise {
  let (_, parsed) = parsed_file(path)
  let tree = @moonflame.aggregate(parsed.samples, max_depth~)
  if tree.total <= 0.0 {
    fail("no positive-weight samples in " + path)
  }
  let pending = tree.roots.copy()
  while pending.length() > 0 {
    let node = pending[pending.length() - 1]
    ignore(pending.pop())
    if node.name == @moonflame.deeper_placeholder() {
      eprintln(
        "moonflame: depth-limited profile; (deeper) contains unexpanded frames",
      )
      break
    }
    for child in node.children {
      pending.push(child)
    }
  }
  tree
}

///|
fn picture(config : @cli.Config, tree : @moonflame.CallTree) -> String raise {
  let layout = @moonflame.layout(
    tree,
    config.width - 2.0 * @moonflame.CANVAS_XPAD,
    @moonflame.FRAME_HEIGHT,
    inverted=config.inverted,
  )
  @moonflame.render_svg(layout, unit=config.unit)
}

///|
fn output(config : @cli.Config) -> String raise {
  if config.action is @cli.Filter(pattern) {
    let (text, parsed) = parsed_file(config.input)
    // Validate accumulation too, even though filtering preserves original lines.
    ignore(@moonflame.aggregate(parsed.samples, max_depth=32))
    return @moonflame.filter_folded(text, pattern)
  }
  let tree = tree_of_file(config.input, config.max_depth)
  match config.action {
    @cli.Render => picture(config, tree)
    @cli.Diff | @cli.Delta(_) => {
      guard config.second is Some(path) else { fail("missing baseline") }
      let before = tree_of_file(path, config.max_depth)
      match config.action {
        @cli.Diff => picture(config, @moonflame.diff_against(tree, before))
        @cli.Delta(count) =>
          @moonflame.render_delta(
            @moonflame.compute_delta(before, tree, count),
            before.total,
            tree.total,
            config.unit,
          )
        _ => abort("unreachable")
      }
    }
    @cli.Hotspots(count) =>
      @moonflame.render_hotspots(
        @moonflame.top_hotspots(tree, count),
        tree.total,
        config.unit,
      )
    @cli.Callers(wanted) =>
      @moonflame.render_relations(
        @moonflame.find_callers(tree, wanted),
        wanted,
        "调用者",
        config.unit,
        matched=@moonflame.has_matching_frame(tree, wanted),
      )
    @cli.Callees(wanted) =>
      @moonflame.render_relations(
        @moonflame.find_callees(tree, wanted),
        wanted,
        "被调用",
        config.unit,
        matched=@moonflame.has_matching_frame(tree, wanted),
      )
    @cli.Filter(_) => abort("unreachable")
  }
}

///|
#cfg(target="js")
fn app_args() -> Array[String] {
  @env.args()[2:].to_owned()
}

///|
#cfg(not(target="js"))
fn app_args() -> Array[String] {
  @env.args()[1:].to_owned()
}

///|
fn error_message(error : Error) -> String {
  match error {
    @fs.IOError(message) => message
    @moonflame.InvalidWeight(message) => message
    @moonflame.InvalidTree(message) => message
    @moonflame.InvalidGeometry(message) => message
    _ => error.to_string()
  }
}
