///|
/// 黑盒测试：符号名归一化。
///
/// 下面用到的名字**全部取自真实采样数据**（`testdata/demo.folded` 与
/// `testdata/stress-recursive.folded`），不是编造的。

///|
test "demangles length-prefixed names from real data" {
  // 上游没能还原的形式：<根><N><段><N><段>
  assert_eq(
    @moonflame.normalize_name("moonflame4demo13run__workload"),
    "moonflame::demo::run_workload",
  )
  assert_eq(
    @moonflame.normalize_name("moonflame4demo3fib"),
    "moonflame::demo::fib",
  )
  assert_eq(@moonflame.normalize_name("array5Array3set"), "array::Array::set")
}

///|
test "folds the escaped underscore on already-demangled names" {
  // 上游把源码里的单个 `_` 转义成了 `__`，还原时没折回去
  assert_eq(
    @moonflame.normalize_name("moonflame::demo::bubble__sort"),
    "moonflame::demo::bubble_sort",
  )
  assert_eq(
    @moonflame.normalize_name("moonflame::demo::build__strings"),
    "moonflame::demo::build_strings",
  )
  assert_eq(
    @moonflame.normalize_name("moonflame::demo::bench__sorting"),
    "moonflame::demo::bench_sorting",
  )
}

///|
test "demangles before folding" {
  // 顺序错了就会失败：先折叠的话 `13run__workload` 只剩 12 个字符，
  // 长度前缀 13 就对不上，还原随之放弃。
  assert_eq(
    @moonflame.normalize_name("moonflame4demo13run__workload"),
    "moonflame::demo::run_workload",
  )
}

///|
test "folds escaped underscores in every real naming style" {
  // 这些名字里的 `__` 同样是上游转义的产物，应当折回单个下划线
  assert_eq(@moonflame.normalize_name("Eq::not__equal"), "Eq::not_equal")
  assert_eq(@moonflame.normalize_name("brute__force__find"), "brute_force_find")
  assert_eq(
    @moonflame.normalize_name("int::Int::to__string_2einner"),
    "int::Int::to_string_2einner",
  )
  assert_eq(
    @moonflame.normalize_name("int__to__string__dec"),
    "int_to_string_dec",
  )
}

///|
test "leaves names alone when they carry no artifact" {
  // 长度前缀对不上、又没有转义下划线的名字，必须原样保留
  for
    name in [
      "sha256_finalize", "utf16le", "base64encode", "md5hash", "moonbit.string_literal",
      "moonbit.add_string", "string::String::contains", "array::Array::at", "string::StringView::find",
    ] {
    assert_eq(@moonflame.normalize_name(name), name)
  }
  // 长度前缀声明与实际字符数不符时放弃还原（只折叠下划线，不拼 `::`）
  assert_eq(@moonflame.normalize_name("sha256_finalize"), "sha256_finalize")
}

///|
test "never rewrites a name that starts with an underscore" {
  // `__libc_start_main` 的双下划线是货真价实的，折叠会改错名字
  assert_eq(@moonflame.normalize_name("__libc_start_main"), "__libc_start_main")
  assert_eq(@moonflame.normalize_name("____moonbit__main"), "____moonbit__main")
}

///|
test "gives up on degenerate inputs without crashing" {
  for name in ["", "123", "0", "1x", "abc"] {
    let result = @moonflame.normalize_name(name)
    // 只要不崩、且是确定性的即可
    assert_eq(result, @moonflame.normalize_name(name))
  }
  // 纯数字开头无法确定根名，必须原样返回
  assert_eq(@moonflame.normalize_name("123"), "123")
}

///|
test "is idempotent for already-clean names" {
  for
    name in ["main", "(self)", "(deeper)", "(root)", "moonflame::demo::matmul"] {
    assert_eq(@moonflame.normalize_name(name), name)
    assert_eq(@moonflame.normalize_name(@moonflame.normalize_name(name)), name)
  }
}

///|
test "the parser still preserves the original names verbatim" {
  // 归一化只发生在渲染层：解析层必须原样保留，否则折叠栈数据会被改写
  let sample = @moonflame.parse_line(
    "____moonbit__main;moonflame4demo13run__workload;array5Array3set 1",
  )
  guard sample is Some(s) else { fail("expected a sample") }
  assert_true(
    s.frames ==
    ["____moonbit__main", "moonflame4demo13run__workload", "array5Array3set"],
  )
}
