///|
/// 折叠栈（folded stack）格式的解析。
///
/// 输入格式为每行一条样本：
///
///     <帧1>;<帧2>;<帧3>;<...> <权重>
///
/// 约定与实现要点：
///
///   - 帧之间用分号分隔，**最后一个空格**之后是权重，因此帧名内部允许含空格；
///   - 权重按浮点解析：上游 moon-pprof 输出的是**纳秒时间**，不是整数采样计数；
///   - 空帧名统一兜底为 `(root)`——真实数据里出现过 `:ackermann;...` 这类以空帧
///     开头的栈；
///   - 空白行直接忽略，非空但无法解析的行计入 `skipped_lines`。

///|
/// 一个采样样本：一条调用栈 + 权重。
///
/// `frames` 自顶向下排列，`frames[0]` 为根帧。
pub struct Sample {
  frames : Array[String]
  weight : Double
} derive(Eq)

///|
/// 显式声明 `Eq` 的方法可被当作常规方法调用。
///
/// 新版编译器不再自动完成这个提升，不声明会报 `implicit_impl_as_method`。
pub extend Sample with Eq::{not_equal, equal}

///|
/// 解析结果。`skipped_lines` 记录非空但无法解析的行数，便于调用方提示用户。
pub struct ParseResult {
  samples : Array[Sample]
  skipped_lines : Int
} derive(Eq)

///|
/// 显式声明 `Eq` 的方法可被当作常规方法调用。
///
/// 新版编译器不再自动完成这个提升，不声明会报 `implicit_impl_as_method`。
pub extend ParseResult with Eq::{not_equal, equal}

///|
/// 解析权重。无法解析或为非有限值（NaN / Inf）时返回 `None`——
/// 这类值会让后续布局的比例计算整体失效，必须在入口拦掉。
fn parse_weight(view : StringView) -> Double? {
  let parsed : Result[Double, Error] = Ok(@string.parse_double(view)) catch {
    error => Err(error)
  }
  match parsed {
    Ok(value) =>
      if value.is_nan() || value.is_inf() {
        None
      } else {
        Some(value)
      }
    Err(_) => None
  }
}

///|
/// 解析一行折叠栈。
///
/// 返回 `None` 表示该行不是有效样本，由调用方决定是忽略还是计入跳过数。
pub fn parse_line(line : StringView) -> Sample? {
  let trimmed = line.trim()
  if trimmed.is_empty() {
    return None
  }
  // 最后一个空格分隔「栈」与「权重」
  guard trimmed.rev_find(" ") is Some(sep) else { return None }
  let stack_part = trimmed.view(end_offset=sep)
  let weight_part = trimmed.view(start_offset=sep + 1)
  guard parse_weight(weight_part) is Some(weight) else { return None }
  let frames : Array[String] = []
  for raw in stack_part.split(";") {
    let name = raw.trim()
    frames.push(if name.is_empty() { "(root)" } else { name.to_owned() })
  }
  guard frames.length() > 0 else { return None }
  Some({ frames, weight, })
}

///|
/// 解析整个折叠栈文本。
///
/// 空白行被直接忽略；非空但无法解析的行计入 `skipped_lines`。
pub fn parse_folded(text : String) -> ParseResult {
  let samples : Array[Sample] = []
  let mut skipped = 0
  for line in text.split("\n") {
    match parse_line(line) {
      Some(sample) => samples.push(sample)
      None => if !line.is_blank() { skipped = skipped + 1 }
    }
  }
  { samples, skipped_lines: skipped, }
}
