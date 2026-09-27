///|
/// MoonFlame 命令行入口。
///
/// 当前阶段仅打印版本与用法；参数解析与各子命令将在后续提交中加入。

///|
fn main {
  println("moonflame \{@moonflame.version()}")
  println("")
  println("Render folded stack profiles into interactive SVG flame graphs.")
  println("")
  println("Usage:")
  println("  moonflame render <input.folded> --out <flame.svg>")
  println("  moonflame render <input.folded> --max-depth <n>")
  println("  moonflame render <input.folded> --top <n>")
  println("  moonflame diff <before.folded> <after.folded> --out <diff.svg>")
}
