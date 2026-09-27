///|
/// 符号名归一化。
///
/// 上游的符号还原并不完整，真实数据里
/// 会同时出现几种形态的名字：
///
/// | 形态 | 真实例子 | 归一化后 |
/// | --- | --- | --- |
/// | 已还原 | `moonflame::demo::bubble__sort` | `moonflame::demo::bubble_sort` |
/// | 长度前缀未还原 | `moonflame4demo13run__workload` | `moonflame::demo::run_workload` |
/// | 部分还原 | `array5Array3set` | `array::Array::set` |
/// | 点号分隔 | `moonbit.add_string` | 不变 |
///
/// **这层只在渲染时生效，解析层一律原样保留**——`folded.mbt` 不做任何猜测性修正，
/// 因此折叠栈数据本身不会因为显示而被改变。
///
/// 长度前缀的还原是**自校验**的：每段声明的长度必须与后面的字符数完全吻合，
/// 否则整体放弃（返回 `None`）。这条约束让 `sha256_finalize`、`utf16le`、
/// `base64encode` 这类名字不会被误改。

///|
fn is_ascii_digit(c : Char) -> Bool {
  let code = Char::to_int(c)
  code >= 48 && code <= 57
}

///|
/// 把长度前缀修饰名还原成 `::` 分隔的形式。无法可靠还原时返回 `None`。
///
/// 形如 `<根><N><段><N><段>…`，其中每段的 `N` 是十进制的字符数。
fn demangle_length_prefixed(name : String) -> String? {
  let chars = name.to_array()
  let total = chars.length()
  if total == 0 {
    return None
  }
  // 根：开头连续的非数字。整串都是数字、或一开头就是数字，都视为无法还原。
  let mut index = 0
  while index < total && !is_ascii_digit(chars[index]) {
    index = index + 1
  }
  if index == 0 || index >= total {
    return None
  }
  let root = String::from_array(chars[0:index])
  let segments : Array[String] = []
  while index < total {
    let digits_start = index
    let mut length = 0
    while index < total && is_ascii_digit(chars[index]) {
      // 位数过多必然不可能是长度前缀，直接放弃以免整数溢出
      if index - digits_start >= 7 {
        return None
      }
      length = length * 10 + (Char::to_int(chars[index]) - 48)
      index = index + 1
    }
    if index == digits_start {
      // 期望长度前缀却读到非数字
      return None
    }
    if length <= 0 || index + length > total {
      // 声明的长度与实际字符数不符 —— 这不是修饰名
      return None
    }
    segments.push(String::from_array(chars[index:index + length]))
    index = index + length
  }
  if segments.length() == 0 {
    return None
  }
  Some(root + "::" + segments.join("::"))
}

///|
/// 折叠重复下划线。
///
/// 上游把源码里的单个 `_` 转义成了 `__`，但还原时没有折回，于是
/// `bubble_sort` 显示成 `bubble__sort`。
///
/// **以 `_` 开头的名字不动**：`__libc_start_main`、`____moonbit__main`
/// 这类是货真价实的双下划线开头，折叠反而会改写正确的名字。
fn fold_double_underscore(name : String) -> String {
  if name.has_prefix("_") {
    name
  } else {
    name.replace_all(old="__", new="_")
  }
}

///|
/// 把上游未还原的符号名归一化成可读形式。
///
/// 顺序很重要：**先还原长度前缀，再折叠下划线**。
/// 反过来的话，`13run__workload` 被折成 12 个字符后长度前缀就对不上了。
pub fn normalize_name(name : String) -> String {
  let demangled = match demangle_length_prefixed(name) {
    Some(decoded) => decoded
    None => name
  }
  fold_double_underscore(demangled)
}
