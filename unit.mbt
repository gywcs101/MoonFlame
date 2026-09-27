///|
/// 权重的单位与格式化。
///
/// 折叠栈格式里第 2 列是**不透明的权重**，不同产出者含义完全不同：
///
/// | 产出者 | 权重含义 |
/// | --- | --- |
/// | `moon-pprof`（`pprof2folded`） | 纳秒时间 |
/// | `perf`、`py-spy`、`async-profiler` | 采样计数 |
///
/// 数值本身无法区分这两者（`42` 既可能是 42 纳秒也可能是 42 次采样），
/// 所以单位必须由使用者声明。默认纳秒——与本项目文档中的主链路一致。

///|
/// 权重单位。
///
/// 注意名字**不能**叫 `Unit`：那是 MoonBit 的内置类型，重名会遮蔽它，
/// 导致全仓库所有 `-> Unit` 的函数都报出「has type Unit, wanted Unit」这类怪错。
pub(all) enum WeightUnit {
  /// 采样计数（`perf` 等）。显示为带千位分隔的整数，不带单位后缀。
  Count
  /// 纳秒（默认）
  Nanoseconds
  Microseconds
  Milliseconds
  Seconds
} derive(Eq)

///|
/// 显式声明 `Eq` 的方法可被当作常规方法调用。
///
/// 新版编译器不再自动完成这个提升，不声明会报 `implicit_impl_as_method`。
pub extend WeightUnit with Eq::{not_equal, equal}

///|
/// 从命令行文本解析单位。无法识别时返回 `None`。
pub fn WeightUnit::parse(text : String) -> WeightUnit? {
  match text.to_lower() {
    "count" | "counts" | "samples" | "sample" => Some(Count)
    "ns" | "nanoseconds" | "nanosecond" => Some(Nanoseconds)
    "us" | "µs" | "microseconds" | "microsecond" => Some(Microseconds)
    "ms" | "milliseconds" | "millisecond" => Some(Milliseconds)
    "s" | "sec" | "secs" | "seconds" | "second" => Some(Seconds)
    _ => None
  }
}

///|
/// 单位的规范写法，用于帮助信息与报告表头。
pub fn WeightUnit::label(self : WeightUnit) -> String {
  match self {
    Count => "count"
    Nanoseconds => "ns"
    Microseconds => "us"
    Milliseconds => "ms"
    Seconds => "s"
  }
}

///|
/// 一个单位的权重折算成纳秒。`Count` 不适用，返回 1。
fn WeightUnit::to_nanoseconds(self : WeightUnit) -> Double {
  match self {
    Count => 1.0
    Nanoseconds => 1.0
    Microseconds => 1000.0
    Milliseconds => 1000000.0
    Seconds => 1000000000.0
  }
}

///|
/// 保留最多两位小数，去掉多余的尾零。
fn format_scaled(value : Double) -> String {
  let negative = value < 0.0
  let magnitude = if negative { -value } else { value }
  let scaled = (magnitude * 100.0 + 0.5).to_int()
  let whole = scaled / 100
  let frac = scaled % 100
  let sign = if negative { "-" } else { "" }
  if frac == 0 {
    sign + whole.to_string()
  } else if frac % 10 == 0 {
    sign + whole.to_string() + "." + (frac / 10).to_string()
  } else if frac < 10 {
    sign + whole.to_string() + ".0" + frac.to_string()
  } else {
    sign + whole.to_string() + "." + frac.to_string()
  }
}

///|
/// 按数量级自动选择易读的时间单位，与 `go tool pprof` 的做法一致。
fn format_duration(nanoseconds : Double) -> String {
  let magnitude = if nanoseconds < 0.0 { -nanoseconds } else { nanoseconds }
  if magnitude >= 1000000000.0 {
    format_scaled(nanoseconds / 1000000000.0) + " s"
  } else if magnitude >= 1000000.0 {
    format_scaled(nanoseconds / 1000000.0) + " ms"
  } else if magnitude >= 1000.0 {
    format_scaled(nanoseconds / 1000.0) + " µs"
  } else {
    format_scaled(nanoseconds) + " ns"
  }
}

///|
/// 给整数加千位分隔符。`perf` 的采样计数动辄六七位，不隔开很难读。
fn add_commas(digits : String) -> String {
  let negative = digits.has_prefix("-")
  let body = if negative { digits[1:] } else { digits }
  let sb = StringBuilder()
  if negative {
    sb.write_string("-")
  }
  let n = body.length()
  for i = 0; i < n; i = i + 1 {
    if i > 0 && (n - i) % 3 == 0 {
      sb.write_string(",")
    }
    sb.write_string(body[i:i + 1].to_owned())
  }
  sb.to_string()
}

///|
/// 把权重格式化成人能读的文本。
///
/// 时间单位按数量级自动缩放（`871808200` 纳秒 → `871.8 ms`）；
/// 计数则原样显示并加千位分隔（`1234567` → `1,234,567`），不加后缀——
/// 加了反而会让人误以为它是时间。
pub fn format_weight(value : Double, unit : WeightUnit) -> String {
  match unit {
    Count => {
      // 负数朝绝对值更大的方向取整，否则 -1200000 会被写成 -1199999
      let rounded = (if value < 0.0 { value - 0.5 } else { value + 0.5 }).to_int()
      if rounded.to_double() == value {
        add_commas(rounded.to_string())
      } else {
        value.to_string()
      }
    }
    _ => format_duration(value * WeightUnit::to_nanoseconds(unit))
  }
}

///|
/// 带符号的变化量，正数带 `+` 便于识别。
pub fn format_signed_weights(value : Double, unit : WeightUnit) -> String {
  if value > 0.0 {
    "+" + format_weight(value, unit)
  } else {
    format_weight(value, unit)
  }
}
