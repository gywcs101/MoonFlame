///|
/// 黑盒测试：SVG 渲染。
///
/// 渲染是纯函数：同一份布局必须逐字节产出同一份文本，否则图片无法做快照对比。

///|
fn svg_of(text : String, max_depth : Int) -> String {
  let tree = tree_of(text, max_depth)
  @moonflame.render_svg(
    @moonflame.layout(tree, 1000.0, @moonflame.FRAME_HEIGHT),
  )
}

///|
/// 帧矩形的个数。画布上还有一个铺底的背景 `<rect>`，不能算进帧里。
fn frame_count(svg : String) -> Int {
  count_of(svg, "<g data-name=")
}

///|
test "emits a well-formed svg envelope" {
  let svg = svg_of("main;fft 100", 0)
  assert_true(svg.has_prefix("<svg "))
  assert_true(svg.has_suffix("</svg>\n"))
  assert_true(svg.contains("xmlns=\"http://www.w3.org/2000/svg\""))
  // 画布 = 内容宽度 1000 + 左右留白 10*2；
  // 高度 = 2 行（main → fft/(self)）* 16 + 上留白 36 + 下留白 34
  assert_true(svg.contains("viewBox=\"0 0 1020 102\""))
  assert_true(svg.contains("width=\"1020\" height=\"102\""))
}

///|
test "draws one rect per visible frame" {
  let svg = svg_of("main;compute;fft 900\nmain;compute 100", 0)
  // main / compute / fft 三个真实帧 + compute 的 (self) 合成项
  assert_eq(frame_count(svg), 4)
}

///|
test "wraps every frame in a group carrying its name" {
  // 交互脚本靠 data-name 读帧名，不去解析提示文本
  let svg = svg_of("main;fft 100", 0)
  assert_true(svg.contains("<g id=\"frames\">"))
  assert_true(svg.contains("<g data-name=\"main\">"))
  assert_true(svg.contains("<g data-name=\"fft\">"))
}

///|
test "gives every rect a hover title" {
  let svg = svg_of("main;fft 100", 0)
  // 默认按纳秒解读权重；100 不足 1 µs，因此显示为 "100 ns"
  assert_true(svg.contains("<title>main — 100 ns (100.0%)</title>"))
  assert_true(svg.contains("<title>fft — 100 ns (100.0%)</title>"))
}

///|
test "leaves a one pixel gap between rows" {
  // 行高 16，矩形高度应为 15
  let svg = svg_of("main;fft 100", 0)
  assert_true(svg.contains("height=\"15\""))
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
test "colours every frame with the classic hot palette" {
  // 经典实现的 hot 调色板公式：r = 205+50v、g = 230v、b = 55v（v 由名称哈希决定）。
  // 因此红通道恒 >= 205、蓝通道恒 <= 55——这是「暖色单维渐变」的判据。
  for
    name in [
      "", "main", "a&b<c>d", "mizchi::bench::ackermann", "____moonbit__main", "(self)",
      "(deeper)", "(root)",
    ] {
    let fill = @moonflame.fill_of(name)
    assert_true(fill.has_prefix("rgb("))
    assert_true(fill.has_suffix(")"))
    let parts = fill[4:fill.length() - 1].split(",").collect()
    assert_eq(parts.length(), 3)
    let r = @string.parse_int(parts[0]) catch { _ => -1 }
    let g = @string.parse_int(parts[1]) catch { _ => -1 }
    let b = @string.parse_int(parts[2]) catch { _ => -1 }
    assert_true(r >= 205 && r <= 255)
    assert_true(g >= 0 && g <= 230)
    assert_true(b >= 0 && b <= 55)
  }
}

///|
test "no frame is coloured grey" {
  // 合成帧也走同一套配色：灰色在浅色背景上读不出名字，不再使用
  for name in ["(self)", "(deeper)", "(root)", ""] {
    let fill = @moonflame.fill_of(name)
    let parts = fill[4:fill.length() - 1].split(",").collect()
    let r = @string.parse_int(parts[0]) catch { _ => -1 }
    let b = @string.parse_int(parts[2]) catch { _ => -1 }
    // 灰色的特征是三通道相等；暖色调色板下蓝通道必然远小于红通道
    assert_true(r - b >= 150)
  }
}

///|
test "the same name always yields the same colour" {
  // 确定性：颜色只取决于名字，跨运行、跨后端都不变
  assert_eq(
    @moonflame.fill_of("moonflame::demo::walk__tree"),
    @moonflame.fill_of("moonflame::demo::walk__tree"),
  )
  // 同名同色，即便名字里有特殊字符
  assert_eq(@moonflame.fill_of("a&b"), @moonflame.fill_of("a&b"))
}

///|
test "draws labels only when they fit" {
  let tree = tree_of("main;fft 100", 0)
  // 画布很窄时放不下 "main"，帧标签不该出现
  let narrow = @moonflame.render_svg(
    @moonflame.layout(tree, 20.0, @moonflame.FRAME_HEIGHT),
  )
  assert_true(!narrow.contains(">main<"))
  let wide = @moonflame.render_svg(
    @moonflame.layout(tree, 1000.0, @moonflame.FRAME_HEIGHT),
  )
  assert_true(wide.contains(">main<"))
}

///|
test "skips rects below the minimum width" {
  let tree = tree_of("root;a 999\nroot;b 1", 0)
  let svg = @moonflame.render_svg(
    @moonflame.layout(tree, 1000.0, @moonflame.FRAME_HEIGHT),
    min_width=50.0,
  )
  // b 只有 1 像素宽，应当被跳过
  assert_true(!svg.contains("data-name=\"b\""))
  assert_true(svg.contains("data-name=\"a\""))
}

///|
test "can disable labels" {
  let tree = tree_of("main;fft 100", 0)
  let svg = @moonflame.render_svg(
    @moonflame.layout(tree, 1000.0, @moonflame.FRAME_HEIGHT),
    show_labels=false,
  )
  assert_true(!svg.contains(">main<"))
  // 悬停提示仍然保留
  assert_true(svg.contains("<title>"))
}

///|
test "embeds the interaction script and its ui" {
  let svg = svg_of("main;fft 100", 0)
  assert_true(svg.contains("<script type=\"text/ecmascript\">"))
  assert_true(svg.contains("onload=\"init()\""))
  // 四个交互控件缺一不可：搜索、重置缩放、大小写开关、命中占比
  assert_true(svg.contains("id=\"search\""))
  assert_true(svg.contains("id=\"unzoom\""))
  assert_true(svg.contains("id=\"ignorecase\""))
  assert_true(svg.contains("id=\"matched\""))
  assert_true(svg.contains("id=\"details\""))
  // 缩放需要知道方向
  assert_true(svg.contains("var INVERTED = false;"))
}

///|
test "the script follows the requested orientation" {
  let tree = tree_of("main;fft 100", 0)
  let svg = @moonflame.render_svg(
    @moonflame.layout(tree, 1000.0, @moonflame.FRAME_HEIGHT, inverted=true),
  )
  assert_true(svg.contains("var INVERTED = true;"))
}

///|
test "paints a light backdrop so white frames stay visible" {
  // 差异模式里「无变化」是纯白；没有底色的话那些帧会与画布糊在一起
  let svg = svg_of("main;fft 100", 0)
  assert_true(svg.contains("linearGradient id=\"background\""))
  assert_true(svg.contains("fill=\"url(#background)\""))
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
  assert_true(svg.contains("viewBox=\"0 0 1020 70\""))
  assert_eq(frame_count(svg), 0)
}
