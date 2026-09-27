///|
/// 黑盒测试：深度限制与深部合并。
///
/// 两条性质要分开看：
///
///   1. **不丢时间**（一致性检查）：无论限制到几层，「全树所有节点的自身耗时之和」
///      都等于总权重。注意这条性质对「直接丢弃」的实现同样成立，因此它只能证明
///      没有算错，**不能**用来区分合并与丢弃。
///   2. **归因正确**（区分性检查）：被截断的那一层，其自身耗时**不包含**更深的部分，
///      而是要单独出现在 `(deeper)` 上。这才是「合并而非丢弃」的关键——
///      见 `attributes merged time to the placeholder` 与 `mixes capped and uncapped stacks`。

///|
fn tree_of(text : String, max_depth : Int) -> @moonflame.CallTree {
  let samples = @moonflame.parse_folded(text).samples
  @moonflame.aggregate(samples, max_depth~)
}

///|
/// 以该节点为根的子树的最大层数。
fn depth_of(node : @moonflame.Node) -> Int {
  let mut deepest = 0
  for child in node.children {
    let d = depth_of(child)
    if d > deepest {
      deepest = d
    }
  }
  deepest + 1
}

///|
/// 整棵树中所有节点的自身耗时之和。
fn total_self_time(node : @moonflame.Node) -> Double {
  let mut sum = node.self_time()
  for child in node.children {
    sum = sum + total_self_time(child)
  }
  sum
}

///|
fn tree_total_self_time(tree : @moonflame.CallTree) -> Double {
  let mut sum = 0.0
  for root in tree.roots {
    sum = sum + total_self_time(root)
  }
  sum
}

///|
test "keeps full depth when no limit is given" {
  let t = tree_of("a;b;c;d;e 100", 0)
  assert_eq(depth_of(t.roots[0]), 5)
  assert_eq(tree_total_self_time(t), 100.0)
}

///|
test "merges deeper frames into a placeholder instead of dropping them" {
  let t = tree_of("a;b;c;d;e 100", 2)
  let root = t.roots[0]
  assert_eq(root.name, "a")
  assert_eq(depth_of(root), 3)
  guard root.child("b") is Some(b) else { fail("missing b") }
  guard b.child(@moonflame.deeper_placeholder()) is Some(deeper) else {
    fail("missing placeholder")
  }
  assert_eq(deeper.value, 100.0)
}

///|
test "attributes merged time to the placeholder, not to the last kept frame" {
  // 这是区分「合并」与「丢弃」的关键用例：
  // 若实现改成丢弃更深帧，b 的自身耗时会变成 100，这个断言就会失败。
  let t = tree_of("a;b;c;d;e 100", 2)
  let root = t.roots[0]
  guard root.child("b") is Some(b) else { fail("missing b") }
  assert_eq(b.value, 100.0)
  assert_eq(b.self_time(), 0.0)
  guard b.child(@moonflame.deeper_placeholder()) is Some(deeper) else {
    fail("missing placeholder")
  }
  assert_eq(deeper.self_time(), 100.0)
}

///|
test "preserves total self time at every depth limit" {
  let text = "a;b;c;d;e 100\na;b;c 50\na;b 25\na 5\nx;y 20"
  for depth in [0, 1, 2, 3, 4, 5, 6, 99] {
    let t = tree_of(text, depth)
    assert_eq(t.total, 200.0)
    assert_eq(tree_total_self_time(t), 200.0)
  }
}

///|
test "caps at depth one" {
  let t = tree_of("a;b;c 100", 1)
  let root = t.roots[0]
  assert_eq(root.name, "a")
  assert_eq(depth_of(root), 2)
  guard root.child(@moonflame.deeper_placeholder()) is Some(deeper) else {
    fail("missing placeholder")
  }
  assert_eq(deeper.value, 100.0)
}

///|
test "does not add a placeholder for stacks within the limit" {
  let t = tree_of("a;b 100", 5)
  let root = t.roots[0]
  assert_eq(depth_of(root), 2)
  guard root.child("b") is Some(b) else { fail("missing b") }
  assert_eq(b.children.length(), 0)
  // 栈正好停在 b，这 100 确实是 b 自身消耗的
  assert_eq(b.self_time(), 100.0)
}

///|
test "mixes capped and uncapped stacks in one tree" {
  // 一条超限、一条正好到上限，两者都要正确处理
  let t = tree_of("a;b;c;d 100\na;b 30", 2)
  let root = t.roots[0]
  guard root.child("b") is Some(b) else { fail("missing b") }
  assert_eq(b.value, 130.0)
  guard b.child(@moonflame.deeper_placeholder()) is Some(deeper) else {
    fail("missing placeholder")
  }
  assert_eq(deeper.value, 100.0)
  // 正好停在上限的那 30 归 b 自己
  assert_eq(b.self_time(), 30.0)
  assert_eq(tree_total_self_time(t), 130.0)
}

///|
test "caps a real 7254-level stack" {
  let depth = 7254
  let recursion = Array::make(depth - 1, "mizchi::bench::ackermann").join(";")
  let text = "____moonbit__main;" + recursion + " 3182800"
  let t = tree_of(text, 32)
  assert_eq(t.total, 3182800.0)
  let root = t.roots[0]
  assert_eq(root.name, "____moonbit__main")
  // 保留 32 层，外加一个 (deeper)
  assert_eq(depth_of(root), 33)
  assert_eq(tree_total_self_time(t), 3182800.0)
}

///|
test "surfaces the merged time in the hotspot report" {
  let t = tree_of("a;b;c;d;e 100", 2)
  let list = @moonflame.top_hotspots(t, 10)
  assert_eq(list.length(), 1)
  assert_eq(list[0].name, "(deeper)")
  assert_eq(list[0].ratio, 1.0)
}
