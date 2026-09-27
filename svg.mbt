///|
/// SVG 渲染：把布局结果拼成 SVG 文本。
///
/// ## 与经典实现的关系
///
/// 图形外观与交互行为对齐 Brendan Gregg 的 FlameGraph（`flamegraph.pl`）：
/// 调色板公式、差异配色、悬停 / 点击缩放 / Ctrl-F 搜索的行为都与之兼容。
///
/// **但代码是独立实现的，没有复制其源码**——那个项目采用 CDDL-1.0（弱 copyleft），
/// 与本项目的 Apache-2.0 不兼容。因此只对齐*功能规格*（配色数值、交互语义），
/// 所有 MoonBit 与 JavaScript 实现均为原创。
///
/// ## 几个要点
///
///   - **颜色无语义**：色相由帧名的稳定哈希决定，只用于让相邻帧可区分；
///     同名同色则让跨图对比时人眼容易追踪；
///   - **每帧一个 `<g>`**，内含 `<title>`（悬停提示）、`<rect>`、`<text>`；
///     JS 通过 `data-name` 读帧名，无需解析提示文本；
///   - **`viewBox` 与 `width`/`height` 分开写**，缩放时图形等比，矢量不失真。

///|
/// 画布左右留白。与经典实现一致，JS 的缩放数学也依赖此值。
pub const CANVAS_XPAD : Double = 10.0

///|
/// 每行高度。经典实现用 16px。
pub const FRAME_HEIGHT : Double = 16.0

///|
/// 基础字号。经典实现用 12px。
pub const BASE_FONT_SIZE : Double = 12.0

///|
/// 字符平均宽度相对字号的比值，用于估算标签能否放下。经典实现用 0.59。
const FONT_WIDTH : Double = 0.59

///|
/// 帧间留缝。经典实现用 1px。
const FRAME_PAD : Double = 1.0

///|
/// 小于该宽度的矩形不绘制。经典实现的默认值是 0.1px。
const MIN_RECT_WIDTH : Double = 0.1

///|
/// 上下留白：顶部容纳标题与按钮，底部容纳信息栏。
fn pad_top(font : Double) -> Double {
  font * 3.0
}

///|
fn pad_bottom(font : Double) -> Double {
  font * 2.0 + 10.0
}

///|
/// 搜索命中时的填充色（品红）。与经典实现同值。
const SEARCH_COLOR : String = "rgb(230,0,230)"

///|
/// 帧名的字节和，对应经典实现的 `sum_namehash`（`unpack("%32W*", $name)`）。
///
/// 注意**不是**经典实现的 `namehash()`：那个函数只读前三个字符
/// （循环里 `last if $mod > 12`），而 MoonBit 的函数名普遍以 `moon`、`array`
/// 等相同前缀开头，会算出大量完全相同的颜色，无法区分相邻帧。
fn sum_namehash(name : String) -> Int64 {
  let mut sum : Int64 = 0L
  for c in name {
    sum = (sum + Char::to_int(c).to_int64()) & 0xFFFFFFFFL
  }
  sum
}

///|
/// 一个 48 位线性同余发生器取首个值，即 `srand48(seed); drand48()`。
///
/// 经典实现的默认配色用 Perl 的 `srand()`/`rand()` 取随机数——那在不同 Perl
/// 构建之间并不稳定，与「同一输入必得同一张图」的确定性目标冲突。
/// 这里用多数平台上 Perl 实际使用的 drand48 算法复现，从而既保持经典观感，
/// 又保证跨运行、跨后端一致。
///
/// 乘法在 48 位上进行，直接算会溢出 64 位，因此把状态拆成高低两段分别取模。
fn drand48_first(seed : Int64) -> Double {
  let mask48 : Int64 = 0xFFFFFFFFFFFFL
  let mask24 : Int64 = 0xFFFFFFL
  let multiplier : Int64 = 0x5DEECE66DL
  // srand48: 低 16 位固定为 0x330E，其余来自种子
  let state = ((seed << 16) | 0x330EL) & mask48
  let high = state >> 24
  let low = state & mask24
  // (A*state + C) mod 2^48，拆成 A*low 与 A*high 两段避免溢出
  let from_low = (multiplier * low) & mask48
  let from_high = ((multiplier * high) & mask24) << 24
  let next = (from_low + from_high + 0xBL) & mask48
  next.to_double() / 281474976710656.0
}

///|
/// 帧名对应的填充色。
///
/// 用经典实现的 `hot` 调色板公式，只是把它的随机分量换成确定性的哈希：
///
/// ```text
/// v = 名称哈希（[0,1)）
/// r = 205 + int(50 * v)
/// g = 0   + int(230 * v)
/// b = 0   + int(55 * v)
/// ```
///
/// 三个通道共用同一个 `v`，因此颜色落成一条**深红 → 橙 → 黄**的单维渐变——
/// 这正是经典火焰图那种暖色观感。
pub fn fill_of(name : String) -> String {
  let v = drand48_first(sum_namehash(name))
  let r = 205 + (50.0 * v).to_int()
  let g = (230.0 * v).to_int()
  let b = (55.0 * v).to_int()
  "rgb(\{r},\{g},\{b})"
}

///|
/// 差异模式的配色：**红 = 变多（劣化）**、**蓝 = 变少（改善）**、**白 = 基本没变**。
///
/// 用经典实现的 `color_scale` 公式：底色是白，随变化幅度向红或蓝加深：
///
/// ```text
/// 变化 > 0:  rgb(255, s, s)   s = 210 * (max - delta) / max
/// 变化 < 0:  rgb(s, s, 255)   s = 210 * (max + delta) / max
/// 变化 = 0:  rgb(255, 255, 255)
/// ```
///
/// 用 `max_delta` 归一化：不归一化的话，只要有一处剧变，
/// 其它所有变化在颜色上就会全糊成一片，等于没画。
///
/// 零变化取**纯白**而不是灰色——灰色在浅色背景上与文字对比度太低，
/// 名字几乎读不出来；纯白配深色文字则清晰可读。
pub fn fill_for_delta(delta : Double, max_delta : Double) -> String {
  if max_delta <= 0.0 {
    return "rgb(255,255,255)"
  }
  if delta > 0.0 {
    let shade = (210.0 * (max_delta - delta) / max_delta).to_int()
    "rgb(255,\{shade},\{shade})"
  } else if delta < 0.0 {
    let shade = (210.0 * (max_delta + delta) / max_delta).to_int()
    "rgb(\{shade},\{shade},255)"
  } else {
    "rgb(255,255,255)"
  }
}

///|
/// 变化量的文本表示，正数带 `+` 号便于识别。
fn format_delta(delta : Double) -> String {
  if delta > 0.0 {
    "+" + format_weight(delta)
  } else {
    format_weight(delta)
  }
}

///|
/// XML 文本转义。`&` 必须最先替换，否则会把后面生成的实体二次转义。
fn escape_xml(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
}

///|
/// 坐标保留一位小数，用于字号等非边界的数值。
fn coord(value : Double) -> String {
  let scaled = (value * 10.0 + 0.5).to_int()
  let whole = scaled / 10
  let frac = scaled % 10
  if frac == 0 {
    whole.to_string()
  } else {
    "\{whole}.\{frac}"
  }
}

///|
/// 把坐标量化到 0.1 像素。
///
/// 相邻矩形**共用的边界会被量化成同一个整数**，因此画出来精确贴合，
/// 不会因为各自四舍五入而留下亚像素裂缝——那种缝在图形被放大后是看得见的。
fn quantize(value : Double) -> Int {
  (value * 10.0 + 0.5).to_int()
}

///|
/// 由量化后的整数生成坐标文本。
fn quantized_text(tenths : Int) -> String {
  let whole = tenths / 10
  let frac = tenths % 10
  if frac == 0 {
    whole.to_string()
  } else {
    "\{whole}.\{frac}"
  }
}

///|
/// 内联的交互脚本。
///
/// 行为对齐经典实现（悬停显示信息、点击缩放、Reset Zoom、Ctrl-F 搜索、
/// Ctrl-I 切换大小写敏感、显示命中占比），但**实现完全原创**。
///
/// 设计取舍：
///   - 每帧的原始几何在 `init()` 里一次性快照进 `orig[]`，
///     因此缩放/复原不需要往元素上写 `_orig_*` 私有属性；
///   - 帧名从 `data-name` 读取，而不是去解析提示文本；
///   - 所有状态（当前搜索词、是否忽略大小写）都存在变量里，不依赖 URL。
fn interaction_script(font : Double, inverted : Bool) -> String {
  let inverted_text = if inverted { "true" } else { "false" }
  [
    "\"use strict\";",
    "var SVG, FRAMES, DETAILS, SEARCHBTN, UNZBTN, MATCHED, ICBTN;",
    "var orig = [], searching = false, term = null, ignorecase = false;",
    "var canvasW = 0;",
    "\nvar XPAD = " + coord(CANVAS_XPAD) + ";",
    "var FONTSIZE = " + coord(font) + ";",
    "var FONTWIDTH = " + coord(FONT_WIDTH) + ";",
    "var INVERTED = " + inverted_text + ";",
    "var SEARCHCOLOR = \"" + SEARCH_COLOR + "\";",
    "var NAMETYPE = \"Function:\";",
    "\nfunction init() {",
    "  SVG = document.getElementsByTagName(\"svg\")[0];",
    "  var box = document.getElementById(\"frames\");",
    "  if (!box) return;",
    "  FRAMES = box.children;",
    "  DETAILS = document.getElementById(\"details\").firstChild;",
    "  SEARCHBTN = document.getElementById(\"search\");",
    "  UNZBTN = document.getElementById(\"unzoom\");",
    "  MATCHED = document.getElementById(\"matched\");",
    "  ICBTN = document.getElementById(\"ignorecase\");",
    "  canvasW = SVG.width.baseVal.value;",
    "  for (var i = 0; i < FRAMES.length; i++) {",
    "    var r = rectOf(FRAMES[i]);",
    "    orig.push({ x: num(r, \"x\"), y: num(r, \"y\"), w: num(r, \"width\"),",
    "                fill: r.getAttribute(\"fill\") });",
    "  }",
    "  wire();",
    "}",
    "\nfunction num(el, attr) { return parseFloat(el.getAttribute(attr)); }",
    "function rectOf(g) { return g.querySelector(\"rect\"); }",
    "function textOf(g) { return g.querySelector(\"text\"); }",
    "function nameOf(g) { return g.getAttribute(\"data-name\") || \"\"; }",
    "function indexOf(g) {",
    "  for (var i = 0; i < FRAMES.length; i++) if (FRAMES[i] === g) return i;",
    "  return -1;",
    "}",
    "function groupOf(node) {",
    "  while (node && node.parentNode && node.parentNode.id !== \"frames\") {",
    "    node = node.parentNode;",
    "  }",
    "  return node && node.parentNode && node.parentNode.id === \"frames\" ? node : null;",
    "}",
    "\nfunction setGeom(g, x, w) {",
    "  var r = rectOf(g), t = textOf(g);",
    "  r.setAttribute(\"x\", x);",
    "  r.setAttribute(\"width\", w);",
    "  if (t) t.setAttribute(\"x\", x + 3);",
    "  fitText(g, x, w);",
    "}",
    "\n// 窄框里写字会溢出，放不下就改成截断加省略号",
    "function fitText(g, x, w) {",
    "  var t = textOf(g);",
    "  if (!t) return;",
    "  var full = nameOf(g);",
    "  var room = w - 6;",
    "  if (room < 2 * FONTSIZE * FONTWIDTH) { t.textContent = \"\"; return; }",
    "  var chars = Math.floor(room / (FONTSIZE * FONTWIDTH));",
    "  t.textContent = chars >= full.length ? full : full.substring(0, chars - 2) + \"..\";",
    "}",
    "\nfunction applyZoom(i) {",
    "  var base = orig[i];",
    "  var xmin = base.x, xmax = base.x + base.w;",
    "  var ratio = (canvasW - 2 * XPAD) / (xmax - xmin);",
    "  var fudge = 0.0001;",
    "  UNZBTN.classList.remove(\"hide\");",
    "  for (var k = 0; k < FRAMES.length; k++) {",
    "    var g = FRAMES[k], o = orig[k];",
    "    var isAncestor = INVERTED ? (o.y < base.y) : (o.y > base.y);",
    "    if (isAncestor) {",
    "      if (o.x <= xmin + fudge && o.x + o.w + fudge >= xmax) {",
    "        g.classList.add(\"parent\");",
    "        setGeom(g, XPAD, canvasW - 2 * XPAD);",
    "      } else { g.classList.add(\"hide\"); }",
    "    } else if (o.x + fudge < xmin || o.x >= xmax - fudge) {",
    "      g.classList.add(\"hide\");",
    "    } else {",
    "      setGeom(g, (o.x - xmin) * ratio + XPAD, o.w * ratio);",
    "    }",
    "  }",
    "  if (term !== null) doSearch();",
    "}",
    "\nfunction resetZoom() {",
    "  UNZBTN.classList.add(\"hide\");",
    "  for (var k = 0; k < FRAMES.length; k++) {",
    "    FRAMES[k].classList.remove(\"parent\");",
    "    FRAMES[k].classList.remove(\"hide\");",
    "    setGeom(FRAMES[k], orig[k].x, orig[k].w);",
    "  }",
    "  if (term !== null) doSearch();",
    "}",
    "\nfunction clearHighlight() {",
    "  for (var k = 0; k < FRAMES.length; k++) {",
    "    rectOf(FRAMES[k]).setAttribute(\"fill\", orig[k].fill);",
    "  }",
    "}",
    "\nfunction doSearch() {",
    "  if (term === null) return;",
    "  var re;",
    "  try { re = new RegExp(term, ignorecase ? \"i\" : \"\"); }",
    "  catch (e) { return; }",
    "  clearHighlight();",
    "  var spans = [], maxw = 0, hit = false;",
    "  for (var k = 0; k < FRAMES.length; k++) {",
    "    var g = FRAMES[k], r = rectOf(g);",
    "    var w = num(r, \"width\");",
    "    if (w > maxw) maxw = w;",
    "    if (re.test(nameOf(g))) {",
    "      r.setAttribute(\"fill\", SEARCHCOLOR);",
    "      spans.push({ x: num(r, \"x\"), w: w });",
    "      hit = true;",
    "    }",
    "  }",
    "  if (!hit) return;",
    "  searching = true;",
    "  SEARCHBTN.classList.add(\"show\");",
    "  SEARCHBTN.firstChild.nodeValue = \"Reset Search\";",
    "  // 命中率按「垂直不重叠」累计：同一列只取最宽的那帧，否则父子会重复计入",
    "  spans.sort(function (a, b) { return a.x - b.x; });",
    "  var count = 0, lastx = -1, lastw = 0, fudge = 0.0001;",
    "  for (var j = 0; j < spans.length; j++) {",
    "    if (spans[j].x >= lastx + lastw - fudge) {",
    "      count += spans[j].w; lastx = spans[j].x; lastw = spans[j].w;",
    "    }",
    "  }",
    "  var pct = 100 * count / maxw;",
    "  MATCHED.classList.remove(\"hide\");",
    "  MATCHED.firstChild.nodeValue = \"Matched: \" + (pct === 100 ? 100 : pct.toFixed(1)) + \"%\";",
    "}",
    "\nfunction resetSearch() {",
    "  searching = false;",
    "  term = null;",
    "  clearHighlight();",
    "  SEARCHBTN.classList.remove(\"show\");",
    "  SEARCHBTN.firstChild.nodeValue = \"Search\";",
    "  MATCHED.classList.add(\"hide\");",
    "  MATCHED.firstChild.nodeValue = \"\";",
    "}",
    "\nfunction searchPrompt() {",
    "  if (searching) { resetSearch(); return; }",
    "  var t = prompt(\"Enter a search term (regexp allowed, eg: ^moon)\" +",
    "    (ignorecase ? \", ignoring case\" : \"\") +",
    "    \"\\nPress Ctrl-i to toggle case sensitivity\", \"\");",
    "  if (t === null) return;",
    "  term = t;",
    "  doSearch();",
    "}",
    "\nfunction toggleIgnoreCase() {",
    "  ignorecase = !ignorecase;",
    "  if (ignorecase) ICBTN.classList.add(\"show\"); else ICBTN.classList.remove(\"show\");",
    "  if (searching) doSearch();",
    "}",
    "\nfunction wire() {",
    "  window.addEventListener(\"click\", function (e) {",
    "    if (e.target.id === \"unzoom\") { resetZoom(); return; }",
    "    if (e.target.id === \"search\") { searchPrompt(); return; }",
    "    if (e.target.id === \"ignorecase\") { toggleIgnoreCase(); return; }",
    "    var g = groupOf(e.target);",
    "    if (g) applyZoom(indexOf(g));",
    "  }, false);",
    "  window.addEventListener(\"mouseover\", function (e) {",
    "    var g = groupOf(e.target);",
    "    if (g) DETAILS.nodeValue = NAMETYPE + \" \" + g.querySelector(\"title\").textContent;",
    "  }, false);",
    "  window.addEventListener(\"mouseout\", function (e) {",
    "    var g = groupOf(e.target);",
    "    if (g) DETAILS.nodeValue = \" \";",
    "  }, false);",
    "  window.addEventListener(\"keydown\", function (e) {",
    "    if (e.keyCode === 114 || (e.ctrlKey && e.keyCode === 70)) {",
    "      e.preventDefault(); searchPrompt();",
    "    } else if (e.ctrlKey && e.keyCode === 73) {",
    "      e.preventDefault(); toggleIgnoreCase();",
    "    }",
    "  }, false);",
    "}",
  ].join("\n")
}

///|
/// 内联样式。与经典实现同构：悬停时才描边（默认不描边，避免糊住白色帧），
/// `.parent` 让缩放后成为背景的祖先帧半透明。
fn inline_style(font : Double) -> String {
  [
    "<style type=\"text/css\">",
    "text { font-family:Verdana; font-size:" +
    coord(font) +
    "px; fill:rgb(0,0,0); }",
    "#search, #ignorecase { opacity:0.1; cursor:pointer; }",
    "#search:hover, #search.show, #ignorecase:hover, #ignorecase.show { opacity:1; }",
    "#title { text-anchor:middle; font-size:" + coord(font + 5.0) + "px }",
    "#unzoom { cursor:pointer; }",
    "#frames > *:hover { stroke:black; stroke-width:0.5; cursor:pointer; }",
    ".hide { display:none; }",
    ".parent { opacity:0.5; }",
    "</style>",
  ].join("\n")
}

///|
/// 把布局渲染成 SVG 文本。
///
/// 画布尺寸 = 布局宽度 + 左右留白，高度 = 布局高度 + 上下留白；
/// 留白用于放置标题、Search / Reset Zoom 按钮与底部信息栏。
///
/// `min_width` 以下的矩形会被跳过（默认 0.1 像素，与经典实现一致）：
/// 布局给出的是精确几何，但 sub-pixel 的矩形画出来也看不见，只会白白撑大文件。
///
/// `show_labels` 控制是否在矩形内写帧名。窄框里写字会溢出，因此按字号粗略
/// 估算宽度，放不下就不画（交互脚本在缩放后也会重新估算并截断）。
pub fn render_svg(
  layout : Layout,
  min_width? : Double,
  font_size? : Double,
  show_labels? : Bool,
) -> String {
  let threshold = match min_width {
    Some(value) => value
    None => MIN_RECT_WIDTH
  }
  let font = match font_size {
    Some(value) => value
    None => BASE_FONT_SIZE
  }
  let labels = match show_labels {
    Some(value) => value
    None => true
  }
  let pad_x = CANVAS_XPAD
  let pad_y_top = pad_top(font)
  let pad_y_bottom = pad_bottom(font)
  let width = layout.width + 2.0 * pad_x
  let height = layout.height() + pad_y_top + pad_y_bottom
  let width_text = quantized_text(quantize(width))
  let height_text = quantized_text(quantize(height))
  let sb = StringBuilder()
  sb.write_string("<svg version=\"1.1\" xmlns=\"http://www.w3.org/2000/svg\"")
  sb.write_string(
    " width=\"" + width_text + "\" height=\"" + height_text + "\"",
  )
  sb.write_string(" viewBox=\"0 0 " + width_text + " " + height_text + "\"")
  sb.write_string(" onload=\"init()\">\n")
  // 背景用经典实现的浅色渐变：白色帧靠它才能被看见
  sb.write_string("<defs>\n")
  sb.write_string(
    "<linearGradient id=\"background\" y1=\"0\" y2=\"1\" x1=\"0\" x2=\"0\">\n",
  )
  sb.write_string("<stop stop-color=\"#eeeeee\" offset=\"5%\"/>\n")
  sb.write_string("<stop stop-color=\"#eeeeb0\" offset=\"95%\"/>\n")
  sb.write_string("</linearGradient>\n</defs>\n")
  sb.write_string(inline_style(font) + "\n")
  sb.write_string(
    "<script type=\"text/ecmascript\"><![CDATA[\n" +
    interaction_script(font, layout.inverted) +
    "\n]]></script>\n",
  )
  sb.write_string(
    "<rect x=\"0\" y=\"0\" width=\"" +
    width_text +
    "\" height=\"" +
    height_text +
    "\" fill=\"url(#background)\"/>\n",
  )
  // 顶部标题、按钮；底部信息栏
  let title_y = quantized_text(quantize(font * 2.0))
  let bottom_y = quantized_text(quantize(height - pad_y_bottom / 2.0))
  // 方向不同，标题也不同（与经典实现一致）
  let title = if layout.inverted { "Icicle Graph" } else { "Flame Graph" }
  sb.write_string(
    "<text id=\"title\" x=\"" +
    quantized_text(quantize(width / 2.0)) +
    "\" y=\"" +
    title_y +
    "\">" +
    title +
    "</text>\n",
  )
  sb.write_string(
    "<text id=\"unzoom\" x=\"" +
    quantized_text(quantize(pad_x)) +
    "\" y=\"" +
    title_y +
    "\" class=\"hide\">Reset Zoom</text>\n",
  )
  sb.write_string(
    "<text id=\"search\" x=\"" +
    quantized_text(quantize(width - pad_x - 100.0)) +
    "\" y=\"" +
    title_y +
    "\">Search</text>\n",
  )
  sb.write_string(
    "<text id=\"ignorecase\" x=\"" +
    quantized_text(quantize(width - pad_x - 16.0)) +
    "\" y=\"" +
    title_y +
    "\">ic</text>\n",
  )
  sb.write_string(
    "<text id=\"details\" x=\"" +
    quantized_text(quantize(pad_x)) +
    "\" y=\"" +
    bottom_y +
    "\"> </text>\n",
  )
  sb.write_string(
    "<text id=\"matched\" x=\"" +
    quantized_text(quantize(width - pad_x - 100.0)) +
    "\" y=\"" +
    bottom_y +
    "\"> </text>\n",
  )
  sb.write_string("<g id=\"frames\">\n")
  for rect in layout.rects {
    if rect.width < threshold {
      continue
    }
    // 高度减留缝；行高过小时退化为不留缝，避免矩形消失
    let box_height = if rect.height > FRAME_PAD {
      rect.height - FRAME_PAD
    } else {
      rect.height
    }
    // 边界先量化再求宽高：相邻矩形共用同一条边界，画出来必然贴合
    let left = quantize(pad_x + rect.x)
    let right = quantize(pad_x + rect.x + rect.width)
    let top = quantize(pad_y_top + rect.y)
    let bottom = quantize(pad_y_top + rect.y + box_height)
    let y_text = quantized_text(top)
    let rect_width = right - left
    // 差异模式下按变化量着色，否则按帧名着暖色
    let fill = match rect.delta {
      Some(delta) => fill_for_delta(delta, layout.max_delta)
      None => fill_of(rect.name)
    }
    let ratio = if layout.total > 0.0 { rect.value / layout.total } else { 0.0 }
    let delta_text = match rect.delta {
      Some(delta) => " " + format_delta(delta)
      None => ""
    }
    let escaped = escape_xml(rect.name)
    // data-name 供交互脚本读取，省去解析提示文本
    sb.write_string("<g data-name=\"" + escaped + "\">")
    sb.write_string(
      "<title>" +
      escaped +
      " — " +
      format_weight(rect.value) +
      " (" +
      format_percent(ratio) +
      ")" +
      delta_text +
      "</title>",
    )
    sb.write_string(
      "<rect x=\"" +
      quantized_text(left) +
      "\" y=\"" +
      y_text +
      "\" width=\"" +
      quantized_text(rect_width) +
      "\" height=\"" +
      quantized_text(bottom - top) +
      "\" fill=\"" +
      fill +
      "\" rx=\"2\" ry=\"2\"/>",
    )
    if labels {
      let room = rect_width.to_double() / 10.0 - 6.0
      let fits = rect.name.char_length().to_double() * font * FONT_WIDTH
      if fits <= room {
        let baseline = rect.y + pad_y_top + (rect.height + font) / 2.0 - 1.0
        sb.write_string(
          "<text x=\"" +
          quantized_text(left + 30) +
          "\" y=\"" +
          coord(baseline) +
          "\">",
        )
        sb.write_string(escaped)
        sb.write_string("</text>")
      }
    }
    sb.write_string("</g>\n")
  }
  sb.write_string("</g>\n")
  sb.write_string("</svg>\n")
  sb.to_string()
}
