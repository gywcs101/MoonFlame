///|
/// 黑盒测试：文本报告（调用关系 / 差异排行 / 栈过滤）。

///|
fn relations_of_text(
  text : String,
  wanted : String,
) -> Array[@moonflame.Relation] {
  @moonflame.find_callers(tree_of(text, 0), wanted)
}

///|
/// 取出条目里某个标签的权重；找不到返回 -1。
fn value_of(relations : Array[@moonflame.Relation], label : String) -> Double {
  for r in relations {
    if r.label == label {
      return r.value
    }
  }
  -1.0
}

///|
test "lists the immediate caller of a function" {
  let found = relations_of_text("main;worker 100\nmain;other 50", "worker")
  assert_eq(found.length(), 1)
  assert_eq(found[0].label, "main")
  assert_eq(found[0].value, 100.0)
  assert_eq(found[0].ratio, 100.0 / 150.0)
}

///|
test "separates multiple callers of the same function" {
  // 同一个函数被多处调用时，应当分别列出而不是合并成一条
  let found = relations_of_text(
    "main;alpha;leaf 100\nmain;beta;leaf 50", "leaf",
  )
  assert_eq(found.length(), 2)
  // 权重降序
  assert_eq(found[0].label, "alpha")
  assert_eq(found[1].label, "beta")
  assert_eq(found[0].value, 100.0)
  assert_eq(found[1].value, 50.0)
}

///|
test "does not double count recursive self edges" {
  // 回归测试：递归自调用曾被逐层累加，算出 369% 这种荒谬占比。
  // 递归深度不应该改变「谁在调用它」的答案。
  let found = relations_of_text(
    "main;rec;rec;rec;rec;leaf 100\nmain;rec 20", "leaf",
  )
  // leaf 的直接调用者只有最深那一层 rec，且只计一次
  assert_eq(found.length(), 1)
  assert_eq(found[0].label, "rec")
  assert_eq(found[0].value, 100.0)
  // 占比必须落在合理区间，绝不能超过 100%
  assert_true(found[0].ratio <= 1.0)
}

///|
test "marks the root frame as its own caller" {
  let found = relations_of_text("main;worker 100", "main")
  assert_eq(found.length(), 1)
  assert_eq(found[0].label, "(根帧)")
}

///|
test "returns nothing for an unknown function" {
  assert_eq(relations_of_text("main;worker 100", "nope").length(), 0)
}

///|
test "matches names after normalization and by substring" {
  // 数据里存的是 `build__strings`，用户按可读名查询也要能命中
  let text = "main;moonflame::demo::build__strings 100"
  assert_eq(relations_of_text(text, "build_strings").length(), 1)
  assert_eq(relations_of_text(text, "build__strings").length(), 1)
  // 子串匹配：不用打全限定名
  assert_eq(relations_of_text(text, "strings").length(), 1)
}

///|
test "aggregates the callees of a function" {
  let tree = tree_of("main;worker;a 60\nmain;worker;a 10\nmain;worker;b 30", 0)
  let found = @moonflame.find_callees(tree, "worker")
  assert_eq(found.length(), 2)
  // 同名子调用被合并
  assert_eq(value_of(found, "a"), 70.0)
  assert_eq(value_of(found, "b"), 30.0)
}

///|
test "reports callees across every occurrence" {
  // worker 出现在两处，两处的子调用都要算进来
  let tree = tree_of("main;one;worker;a 40\nmain;two;worker;b 60", 0)
  let found = @moonflame.find_callees(tree, "worker")
  assert_eq(found.length(), 2)
  assert_eq(value_of(found, "a"), 40.0)
  assert_eq(value_of(found, "b"), 60.0)
}

///|
test "renders a relation report with a header and rows" {
  let tree = tree_of("main;worker 100", 0)
  let report = @moonflame.render_relations(
    @moonflame.find_callers(tree, "worker"),
    "worker",
    "调用者",
    @moonflame.Nanoseconds,
  )
  assert_true(report.contains("worker"))
  assert_true(report.contains("main"))
  assert_true(report.contains("100 ns"))
}

///|
test "says so when a query matches nothing" {
  let tree = tree_of("main;worker 100", 0)
  let report = @moonflame.render_relations(
    @moonflame.find_callers(tree, "nope"),
    "nope",
    "调用者",
    @moonflame.Nanoseconds,
  )
  assert_true(report.contains("没有找到"))
}

///|
test "flags both growth and shrinkage in a delta report" {
  let before = tree_of("root;slower 100\nroot;faster 100", 0)
  let after = tree_of("root;slower 300\nroot;faster 20", 0)
  let entries = @moonflame.compute_delta(before, after, 10)
  assert_eq(entries.length(), 2)
  // 变慢最多的排在最前
  assert_eq(entries[0].name, "slower")
  assert_eq(entries[0].change, 200.0)
  assert_eq(entries[0].before, 100.0)
  assert_eq(entries[0].after, 300.0)
  assert_eq(entries[1].name, "faster")
  assert_eq(entries[1].change, -80.0)
}

///|
test "lists functions that only exist on one side" {
  // 「新出现的开销」和「消失的开销」恰恰是差异分析最关心的两件事
  let before = tree_of("root;gone 100", 0)
  let after = tree_of("root;added 100", 0)
  let entries = @moonflame.compute_delta(before, after, 10)
  assert_eq(entries.length(), 2)
  assert_eq(@moonflame.compute_delta(before, after, 10)[0].name, "added")
  // 只在基线里出现的记成负变化
  let gone = match entries[1].name {
    "gone" => entries[1]
    _ => entries[0]
  }
  assert_eq(gone.before, 100.0)
  assert_eq(gone.after, 0.0)
  assert_eq(gone.change, -100.0)
}

///|
test "truncates a delta report to the requested count" {
  let before = tree_of("root;a 10\nroot;b 20\nroot;c 30", 0)
  let after = tree_of("root;a 1\nroot;b 2\nroot;c 3", 0)
  assert_eq(@moonflame.compute_delta(before, after, 2).length(), 2)
  // 0 表示不截断
  assert_eq(@moonflame.compute_delta(before, after, 0).length(), 3)
}

///|
test "renders a delta report with signed changes" {
  let before = tree_of("root;slower 100", 0)
  let after = tree_of("root;slower 300", 0)
  let report = @moonflame.render_delta(
    @moonflame.compute_delta(before, after, 10),
    before.total,
    after.total,
    @moonflame.Nanoseconds,
  )
  assert_true(report.contains("slower"))
  // 变慢要带显式的 + 号
  assert_true(report.contains("+200 ns"))
}

///|
test "filters stacks by substring" {
  let text = "main;alpha;x 10\nmain;beta;y 20\nmain;alpha;z 30"
  let kept = @moonflame.filter_folded(text, "alpha")
  let lines = kept.split("\n").to_array().filter(fn(l) { !l.is_blank() })
  assert_eq(lines.length(), 2)
  assert_true(!kept.contains("beta"))
}

///|
test "filters by a normalized name" {
  // 数据里是 `build__strings`，用户按 `build_strings` 过滤也要能命中
  let text = "main;moonflame::demo::build__strings 100\nmain;other 20"
  let kept = @moonflame.filter_folded(text, "build_strings")
  assert_true(kept.contains("build__strings"))
  assert_true(!kept.contains("other"))
}

///|
test "never matches the weight column" {
  // 只匹配栈部分，否则像 "42" 这样的模式会误命中权重数字
  let text = "main;alpha 42\nmain;beta 7"
  assert_eq(@moonflame.filter_folded(text, "42"), "")
}

///|
test "returns an empty string when nothing matches" {
  assert_eq(@moonflame.filter_folded("main;alpha 10", "nope"), "")
}

///|
test "keeps the original weights untouched" {
  // 过滤不做归一化，这样两张图之间才能对照
  let text = "main;alpha 1000\nmain;beta 2000"
  assert_true(@moonflame.filter_folded(text, "alpha").contains("1000"))
}
