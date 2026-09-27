///|
/// SVG 渲染：把布局结果拼成 SVG 文本。
///
/// SVG 就是 XML 文本，用 `StringBuilder` 拼出来即可——不需要任何图形库，
/// 也不需要 FFI。几个要点：
///
///   - **交互零成本**：把 `<title>` 作为矩形的子元素，浏览器会自动把它做成
///     悬停提示，不写一行 JavaScript；
///   - **颜色无语义**：色相由帧名的稳定哈希决定，只用于让相邻帧可区分；
///     同名同色则让跨图对比时人眼容易追踪；
///   - **矩形高度减 1 像素**，留出白缝，否则相邻帧会糊成一片；
///   - **`viewBox` 与 `width`/`height` 分开写**，缩放时图形等比，矢量不失真；
///   - **标签按预估宽度决定画不画**——SVG 不会自动排版，窄框里写字会溢出。

///|
/// 帧名的稳定哈希。
///
/// 刻意不用 `String::hash`：颜色必须跨运行、跨后端、跨语言版本保持稳定，
/// 否则同一份输入会渲染出不同的图，快照测试便无从谈起。
/// 这里只用乘加与掩码，所有中间值都落在 32 位安全范围内。
fn name_hash(name : String) -> Int {
  let mut h = 7
  for c in name {
    h = (h * 31 + Char::to_int(c)) & 0xFFFFFF
  }
  h
}

///|
/// 合成帧用中性灰，与真实帧一眼区分：
/// `(self)` 是自身耗时、`(deeper)` 是被合并的更深帧、`(root)` 是空帧兜底。
fn is_synthetic(name : String) -> Bool {
  name == self_placeholder() || name == deeper_placeholder() || name == "(root)"
}

///|
/// 帧名对应的填充色。
///
/// 采用火焰图惯用的**暖色**：色相固定在橙→黄区间，靠明度拉开相邻帧的差异。
/// 全色相彩虹虽然更花哨，但暖色渐变读起来更安静，也是 Brendan Gregg
/// 原始实现的默认调色板（`hot`）。同名同色，便于跨图对比。
pub fn fill_of(name : String) -> String {
  if is_synthetic(name) {
    return "hsl(0,0%,84%)"
  }
  let h = name_hash(name)
  let hue = 12 + h % 44
  let light = 60 + h / 44 % 20
  "hsl(\{hue},78%,\{light}%)"
}

///|
/// 差异模式的配色：**红 = 变多（劣化）**、**蓝 = 变少（改善）**、灰 = 基本没变。
///
/// 用 `max_delta` 归一化：不归一化的话，只要有一处剧变，
/// 其它所有变化在颜色上就会全糊成一片，等于没画。
/// 色深随变化幅度递增，因此一眼能看出哪几处改动最要紧。
pub fn fill_for_delta(delta : Double, max_delta : Double) -> String {
  let ratio = if max_delta > 0.0 {
    (delta / max_delta).clamp(min=-1.0, max=1.0)
  } else {
    0.0
  }
  let magnitude = if ratio < 0.0 { -ratio } else { ratio }
  if magnitude < 0.02 {
    return "hsl(0,0%,93%)"
  }
  let lightness = 88 - (magnitude * 36.0).to_int()
  if ratio > 0.0 {
    "hsl(0,78%,\{lightness}%)"
  } else {
    "hsl(214,78%,\{lightness}%)"
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
/// 坐标保留一位小数，用于字号、viewBox 等非边界的数值。
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
/// 布局产出的坐标都非负，这里不处理负值。
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
/// 把布局渲染成 SVG 文本。
///
/// `min_width` 以下的矩形会被跳过（默认 0.5 像素）：布局给出的是精确几何，
/// 但sub-pixel 的矩形画出来也看不见，只会白白撑大文件。
///
/// `show_labels` 控制是否在矩形内写帧名。SVG 无法测量文本宽度，
/// 这里按字号粗略估算，估算宽度放不下就不画。
pub fn render_svg(
  layout : Layout,
  min_width? : Double,
  font_size? : Double,
  show_labels? : Bool,
) -> String {
  let threshold = match min_width {
    Some(value) => value
    None => 0.5
  }
  let font = match font_size {
    Some(value) => value
    None => 11.0
  }
  let labels = match show_labels {
    Some(value) => value
    None => true
  }
  let height = layout.height()
  let width_text = quantized_text(quantize(layout.width))
  let height_text = quantized_text(quantize(height))
  let sb = StringBuilder()
  sb.write_string("<svg xmlns=\"http://www.w3.org/2000/svg\"")
  sb.write_string(
    " width=\"" + width_text + "\" height=\"" + height_text + "\"",
  )
  sb.write_string(" viewBox=\"0 0 " + width_text + " " + height_text + "\"")
  sb.write_string(" font-family=\"monospace\">\n")
  for rect in layout.rects {
    if rect.width < threshold {
      continue
    }
    // 高度减 1 留出白缝；行高过小时退化为不留缝，避免矩形消失
    let box_height = if rect.height > 1.0 {
      rect.height - 1.0
    } else {
      rect.height
    }
    // 边界先量化再求宽高：相邻矩形共用同一条边界，画出来必然贴合
    let left = quantize(rect.x)
    let right = quantize(rect.x + rect.width)
    let top = quantize(rect.y)
    let bottom = quantize(rect.y + box_height)
    sb.write_string(
      "<rect x=\"" +
      quantized_text(left) +
      "\" y=\"" +
      quantized_text(top) +
      "\"",
    )
    sb.write_string(
      " width=\"" +
      quantized_text(right - left) +
      "\" height=\"" +
      quantized_text(bottom - top) +
      "\"",
    )
    // 差异模式下按变化量着色，否则按帧名着暖色
    let fill = match rect.delta {
      Some(delta) => fill_for_delta(delta, layout.max_delta)
      None => fill_of(rect.name)
    }
    sb.write_string(" fill=\"" + fill + "\"")
    sb.write_string(" stroke=\"#fff\" rx=\"2\" ry=\"2\">")
    // 悬停提示：零 JavaScript 的交互
    let ratio = if layout.total > 0.0 { rect.value / layout.total } else { 0.0 }
    let delta_text = match rect.delta {
      Some(delta) => " " + format_delta(delta)
      None => ""
    }
    sb.write_string(
      "<title>" +
      escape_xml(rect.name) +
      " — " +
      format_weight(rect.value) +
      " (" +
      format_percent(ratio) +
      ")" +
      delta_text +
      "</title>",
    )
    sb.write_string("</rect>\n")
    if labels {
      let estimate = rect.name.char_length().to_double() * font * 0.6
      if estimate + 6.0 <= rect.width {
        let baseline = rect.y + (rect.height + font) / 2.0 - 1.0
        sb.write_string(
          "<text x=\"" +
          quantized_text(left + 30) +
          "\" y=\"" +
          coord(baseline) +
          "\"",
        )
        sb.write_string(" font-size=\"" + coord(font) + "\" fill=\"#1b1f2a\">")
        sb.write_string(escape_xml(rect.name))
        sb.write_string("</text>\n")
      }
    }
  }
  sb.write_string("</svg>\n")
  sb.to_string()
}
