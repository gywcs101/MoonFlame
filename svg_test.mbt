///|
/// 黑盒测试：SVG 渲染。
///
/// 渲染是纯函数：同一份布局必须逐字节产出同一份文本，否则图片无法做快照对比。

///|
fn svg_of(text : String, max_depth : Int) -> String {
  let tree = tree_of(text, max_depth)
  @moonflame.render_svg(@moonflame.layout(tree, 1000.0, 20.0))
}

///|
test "emits a well-formed svg envelope" {
  let svg = svg_of("main;fft 100", 0)
  assert_true(svg.has_prefix("<svg "))
  assert_true(svg.has_suffix("</svg>\n"))
  assert_true(svg.contains("xmlns=\"http://www.w3.org/2000/svg\""))
  assert_true(svg.contains("viewBox=\"0 0 1000 40\""))
  assert_true(svg.contains("width=\"1000\" height=\"40\""))
}

///|
test "draws one rect per visible frame" {
  let svg = svg_of("main;compute;fft 900\nmain;compute 100", 0)
  // main / compute / fft 三个真实帧 + compute 的 (self) 合成项
  assert_eq(count_of(svg, "<rect "), 4)
}

///|
test "gives every rect a hover title" {
  let svg = svg_of("main;fft 100", 0)
  assert_true(svg.contains("<title>main — 100 (100.0%)</title>"))
  assert_true(svg.contains("<title>fft — 100 (100.0%)</title>"))
}

///|
test "leaves a one pixel gap between rows" {
  // 行高 20，矩形高度应为 19
  let svg = svg_of("main;fft 100", 0)
  assert_true(svg.contains("height=\"19\""))
}

///|
test "escapes xml special characters in frame names" {
  let svg = svg_of("main;a&b<c>d 100", 0)
  assert_true(svg.contains("a&amp;b&lt;c&gt;d"))
  assert_true(!svg.contains("a&b<c>d"))
}

///|
test "colours identical frame names identically" {
  // leaf 出现在两条不同路径下，颜色必须一致
  let svg = svg_of("main;a;leaf 10\nmain;b;leaf 20", 0)
  let fill = "fill=\"" + @moonflame.fill_of("leaf") + "\""
  assert_true(svg.contains(fill))
  // 两个 leaf 矩形（分别在 a、b 之下）必须着同一种颜色
  assert_true(count_of(svg, fill) >= 2)
}

///|
test "gives synthetic frames a neutral colour" {
  // 合成帧用灰，和真实帧一眼区分
  assert_eq(@moonflame.fill_of("(self)"), "hsl(0,0%,84%)")
  assert_eq(@moonflame.fill_of("(deeper)"), "hsl(0,0%,84%)")
  assert_eq(@moonflame.fill_of("(root)"), "hsl(0,0%,84%)")
}

///|
test "colours real frames with the warm palette" {
  for
    name in [
      "", "main", "a&b<c>d", "mizchi::bench::ackermann", "____moonbit__main",
    ] {
    let fill = @moonflame.fill_of(name)
    assert_true(fill.has_prefix("hsl("))
    assert_true(!fill.contains("0,0%"))
  }
}

///|
test "draws labels only when they fit" {
  let tree = tree_of("main;fft 100", 0)
  // 画布很窄时连 "main" 都放不下，不该出现标签
  let narrow = @moonflame.render_svg(@moonflame.layout(tree, 20.0, 20.0))
  assert_true(!narrow.contains("<text "))
  let wide = @moonflame.render_svg(@moonflame.layout(tree, 1000.0, 20.0))
  assert_true(wide.contains("<text "))
}

///|
test "skips rects below the minimum width" {
  let tree = tree_of("root;a 999\nroot;b 1", 0)
  let svg = @moonflame.render_svg(
    @moonflame.layout(tree, 1000.0, 20.0),
    min_width=50.0,
  )
  // b 只有 1 像素宽，应当被跳过
  assert_true(!svg.contains(">b<"))
  assert_true(svg.contains(">a<"))
}

///|
test "can disable labels" {
  let tree = tree_of("main;fft 100", 0)
  let svg = @moonflame.render_svg(
    @moonflame.layout(tree, 1000.0, 20.0),
    show_labels=false,
  )
  assert_true(!svg.contains("<text "))
  // 悬停提示仍然保留
  assert_true(svg.contains("<title>"))
}

///|
test "renders deterministically" {
  let text = "main;b;z 30\nmain;a 10\nmain;b;y 20\nx 5"
  assert_eq(svg_of(text, 0), svg_of(text, 0))
}

///|
test "renders an empty layout without crashing" {
  let svg = svg_of("", 0)
  assert_true(svg.has_prefix("<svg "))
  assert_true(svg.contains("viewBox=\"0 0 1000 0\""))
  assert_eq(count_of(svg, "<rect "), 0)
}
