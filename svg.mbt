///|
/// SVG 渲染：把布局结果拼成 SVG 文本。
///
/// ## 与经典实现的关系
///
/// 图形外观与交互行为对齐 Brendan Gregg 的 FlameGraph（`flamegraph.pl`）：
/// 调色板公式、差异配色、悬停 / 点击缩放 / Ctrl-F 搜索的行为都与之兼容。
///
/// **但代码是独立实现的，没有复制其源码**——那个项目采用 CDDL-1.0，
/// 是文件级弱 copyleft（不是宽松许可），为避免许可证混用问题只对齐功能规格，
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
/// 默认最小矩形宽度（像素）。
pub fn default_min_width() -> Double {
  MIN_RECT_WIDTH
}

///|
/// 默认字号。
pub fn default_font_size() -> Double {
  BASE_FONT_SIZE
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
  quantized_text(quantize(value))
}

///|
fn quantize(value : Double) -> Double {
  if value.abs() >= 1.0e14 {
    value * 10.0
  } else {
    (value * 10.0 + 0.5).floor()
  }
}

///|
fn quantized_text(tenths : Double) -> String {
  let value = tenths / 10.0
  if value.abs() >= 1.0e14 {
    return value.to_string()
  }
  let whole = value.to_int64()
  let frac = (tenths - whole.to_double() * 10.0).abs().to_int()
  if frac == 0 {
    whole.to_string()
  } else {
    let sign = if value < 0.0 && whole == 0L { "-" } else { "" }
    sign + whole.to_string() + "." + frac.to_string()
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
  let constants = "var XPAD = " +
    coord(CANVAS_XPAD) +
    "; var FONTSIZE = " +
    coord(font) +
    "; var FONTWIDTH = " +
    coord(FONT_WIDTH) +
    "; var INVERTED = " +
    (if inverted { "true" } else { "false" }) +
    "; var SEARCHCOLOR = \"" +
    SEARCH_COLOR +
    "\";\n"
  constants +
  [
    "\"use strict\";", "var SVG, FRAMES, DETAILS, SEARCHBTN, UNZBTN, MATCHED, ICBTN;",
    "var orig = [], searching = false, term = null, ignorecase = false;", "var canvasW = 0;",
    "function init() {", "  SVG = document.getElementsByTagName(\"svg\")[0];", "  FRAMES = document.getElementById(\"frames\").children;",
    "  DETAILS = document.getElementById(\"details\").firstChild;", "  SEARCHBTN = document.getElementById(\"search\");",
    "  UNZBTN = document.getElementById(\"unzoom\");", "  MATCHED = document.getElementById(\"matched\");",
    "  ICBTN = document.getElementById(\"ignorecase\");", "  canvasW = SVG.width.baseVal.value;",
    "  for (var i = 0; i < FRAMES.length; i++) {", "    var r = rectOf(FRAMES[i]);",
    "    orig.push({x:num(r,\"x\"), y:num(r,\"y\"), w:num(r,\"width\"), fill:r.getAttribute(\"fill\")});",
    "  }", "  wire();", "}", "function num(el, a) { return parseFloat(el.getAttribute(a)); }",
    "function rectOf(g) { return g.querySelector(\"rect\"); }", "function textOf(g) { return g.querySelector(\"text\"); }",
    "function nameOf(g) { return g.getAttribute(\"data-name\") || \"\"; }", "function indexOf(g) { return Array.prototype.indexOf.call(FRAMES,g); }",
    "function groupOf(n) {", "  while(n && n.parentNode && n.parentNode.id !== \"frames\") n=n.parentNode;",
    "  return n && n.parentNode && n.parentNode.id === \"frames\" ? n : null;", "}",
    "function fitText(g,x,w) {", "  var t=textOf(g); if(!t) return;", "  var full=nameOf(g), room=w-6, chars=Math.floor(room/(FONTSIZE*FONTWIDTH));",
    "  var points=Array.from(full);", "  t.textContent=chars<2 ? \"\" : chars>=points.length ? full : points.slice(0,chars-2).join(\"\")+\"..\";",
    "}", "function setGeom(g,x,w) {", "  var r=rectOf(g),t=textOf(g); r.setAttribute(\"x\",x); r.setAttribute(\"width\",w);",
    "  if(t) t.setAttribute(\"x\",x+3); fitText(g,x,w);", "}", "function applyZoom(i) {",
    "  if(i<0 || orig[i].w<=0) return;", "  var base=orig[i], xmin=base.x, xmax=base.x+base.w;",
    "  var ratio=(canvasW-2*XPAD)/base.w, fudge=0.0001;", "  UNZBTN.classList.remove(\"hide\");",
    "  for(var k=0;k<FRAMES.length;k++) {", "    var g=FRAMES[k],o=orig[k];", "    g.classList.remove(\"hide\"); g.classList.remove(\"parent\");",
    "    var ancestor=INVERTED ? o.y<base.y : o.y>base.y;", "    if(ancestor) {",
    "      if(o.x<=xmin+fudge && o.x+o.w+fudge>=xmax) {", "        g.classList.add(\"parent\"); setGeom(g,XPAD,canvasW-2*XPAD);",
    "      } else g.classList.add(\"hide\");", "    } else if(o.x<xmin-fudge || o.x+o.w>xmax+fudge) g.classList.add(\"hide\");",
    "    else setGeom(g,(o.x-xmin)*ratio+XPAD,o.w*ratio);", "  }", "  if(term!==null) doSearch();",
    "}", "function resetZoom() {", "  UNZBTN.classList.add(\"hide\");", "  for(var k=0;k<FRAMES.length;k++) {",
    "    FRAMES[k].classList.remove(\"hide\"); FRAMES[k].classList.remove(\"parent\");",
    "    setGeom(FRAMES[k],orig[k].x,orig[k].w);", "  }", "  if(term!==null) doSearch();",
    "}", "function clearHighlight() {", "  for(var k=0;k<FRAMES.length;k++) rectOf(FRAMES[k]).setAttribute(\"fill\",orig[k].fill);",
    "}", "function doSearch() {", "  if(term===null) return;", "  clearHighlight();",
    "  searching=true; SEARCHBTN.classList.add(\"show\"); SEARCHBTN.firstChild.nodeValue=\"Reset Search\";",
    "  MATCHED.classList.remove(\"hide\");", "  var re;", "  try { re=new RegExp(term,ignorecase?\"i\":\"\"); }",
    "  catch(e) { MATCHED.firstChild.nodeValue=\"Invalid regular expression\"; return; }",
    "  var spans=[];", "  for(var k=0;k<FRAMES.length;k++) {", "    var g=FRAMES[k];",
    "    if(g.classList.contains(\"hide\") || g.classList.contains(\"parent\")) continue;",
    "    if(re.test(nameOf(g))) {", "      var r=rectOf(g), x=num(r,\"x\"), right=x+num(r,\"width\");",
    "      rectOf(g).setAttribute(\"fill\",SEARCHCOLOR);", "      spans.push({x:Math.max(XPAD,x),right:Math.min(canvasW-XPAD,right)});",
    "    }", "  }", "  spans.sort(function(a,b){return a.x-b.x || b.right-a.right;});",
    "  var count=0,end=XPAD;", "  for(var j=0;j<spans.length;j++) {", "    var s=spans[j];",
    "    if(s.right>end) { count+=s.right-Math.max(end,s.x); end=s.right; }", "  }",
    "  var pct=Math.max(0,Math.min(100,100*count/(canvasW-2*XPAD)));", "  MATCHED.firstChild.nodeValue=\"Matched: \"+(pct===100?100:pct.toFixed(1))+\"%\";",
    "}", "function resetSearch() {", "  searching=false; term=null; clearHighlight(); SEARCHBTN.classList.remove(\"show\");",
    "  SEARCHBTN.firstChild.nodeValue=\"Search\"; MATCHED.classList.add(\"hide\"); MATCHED.firstChild.nodeValue=\" \";",
    "}", "function searchPrompt() {", "  if(searching) {resetSearch();return;}",
    "  var t=prompt(\"Enter a regular expression; Ctrl-I toggles case sensitivity\",\"\");",
    "  if(t===null) return; term=t;doSearch();", "}", "function toggleIgnoreCase() {",
    "  ignorecase=!ignorecase; ICBTN.classList.toggle(\"show\",ignorecase);", "  if(term!==null) doSearch();",
    "}", "function wire() {", "  window.addEventListener(\"click\",function(e){",
    "    if(e.target.id===\"unzoom\") {resetZoom();return;}", "    if(e.target.id===\"search\") {searchPrompt();return;}",
    "    if(e.target.id===\"ignorecase\") {toggleIgnoreCase();return;}", "    var g=groupOf(e.target);if(g) applyZoom(indexOf(g));",
    "  });", "  window.addEventListener(\"mouseover\",function(e){var g=groupOf(e.target);if(g) DETAILS.nodeValue=\"Function: \"+g.querySelector(\"title\").textContent;});",
    "  window.addEventListener(\"mouseout\",function(e){if(groupOf(e.target)) DETAILS.nodeValue=\" \";});",
    "  window.addEventListener(\"keydown\",function(e){", "    if(e.keyCode===114 || (e.ctrlKey && e.keyCode===70)){e.preventDefault();searchPrompt();}",
    "    else if(e.ctrlKey && e.keyCode===73){e.preventDefault();toggleIgnoreCase();}",
    "  });", "}",
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
///
/// `unit` 决定悬停提示里绝对值的显示方式；`normalize_names` 控制是否把上游
/// 未还原的符号名归一化（只影响显示，解析层始终原样保留）。
pub fn render_svg(
  layout : Layout,
  min_width? : Double,
  font_size? : Double,
  show_labels? : Bool,
  unit? : WeightUnit,
  normalize_names? : Bool,
) -> String raise ValidationError {
  validate_layout(layout)
  let threshold = match min_width {
    Some(value) => value
    None => MIN_RECT_WIDTH
  }
  let font = match font_size {
    Some(value) => value
    None => BASE_FONT_SIZE
  }
  positive_geometry(font, "font_size")
  if !finite(threshold) || threshold < 0.0 {
    raise InvalidGeometry("invalid min_width")
  }
  let labels = match show_labels {
    Some(value) => value
    None => true
  }
  let weight_unit = match unit {
    Some(value) => value
    None => Nanoseconds
  }
  let normalize = match normalize_names {
    Some(value) => value
    None => true
  }
  let pad_x = CANVAS_XPAD
  let pad_y_top = pad_top(font)
  let pad_y_bottom = pad_bottom(font)
  let width = layout.width + 2.0 * pad_x
  let height = layout.height() + pad_y_top + pad_y_bottom
  if !finite(width * 10.0) || !finite(height * 10.0) || !finite(font * 10.0) {
    raise InvalidGeometry("canvas overflow")
  }
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
    if rect_width <= 0.0 {
      continue
    }
    // 差异模式下按变化量着色，否则按帧名着暖色
    let fill = match rect.delta {
      Some(delta) => fill_for_delta(delta, layout.max_delta)
      None => fill_of(rect.name)
    }
    let ratio = if layout.total > 0.0 { rect.value / layout.total } else { 0.0 }
    let delta_text = match rect.delta {
      Some(delta) => " " + format_signed_weights(delta, weight_unit)
      None => ""
    }
    // 显示名可以归一化；`data-name` 与提示文本里的原名保持可追溯
    let shown = if normalize { normalize_name(rect.name) } else { rect.name }
    let escaped = escape_xml(shown)
    let original = escape_xml(rect.name)
    // data-name 供交互脚本读取，省去解析提示文本
    sb.write_string("<g data-name=\"" + escaped + "\">")
    sb.write_string(
      "<title>" +
      escaped +
      " — " +
      format_weight(rect.value, weight_unit) +
      " (" +
      format_percent(ratio) +
      ")" +
      delta_text,
    )
    // 名字被归一化过时，把原名附在提示里，信息不丢失
    if shown != rect.name {
      sb.write_string("&#10;原名: " + original)
    }
    sb.write_string("</title>")
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
      let room = rect_width / 10.0 - 6.0
      let fits = shown.char_length().to_double() * font * FONT_WIDTH
      let baseline = rect.y + pad_y_top + (rect.height + font) / 2.0 - 1.0
      sb.write_string(
        "<text x=\"" +
        quantized_text(left + 30.0) +
        "\" y=\"" +
        coord(baseline) +
        "\">",
      )
      if fits <= room {
        sb.write_string(escaped)
      }
      sb.write_string("</text>")
    }
    sb.write_string("</g>\n")
  }
  sb.write_string("</g>\n")
  sb.write_string("</svg>\n")
  sb.to_string()
}
