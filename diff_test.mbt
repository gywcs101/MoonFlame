///|
/// 黑盒测试：差异火焰图（数据标注 + 配色）。
///
/// 语义约定：**红 = 变多（劣化）**、**蓝 = 变少（改善）**、灰 = 基本没变。
/// 宽度始终按「当前」剖面走，因此只在基线里出现的帧不会显示。

///|
fn diff_of(before : String, after : String) -> @moonflame.CallTree {
  @moonflame.diff_against(tree_of(after, 0), tree_of(before, 0))
}

///|
fn child_named(node : @moonflame.Node, name : String) -> @moonflame.Node raise {
  match node.child(name) {
    Some(value) => value
    None => fail("missing child: " + name)
  }
}

///|
fn delta_of(node : @moonflame.Node) -> Double raise {
  match node.delta {
    Some(value) => value
    None => fail("node has no delta: " + node.name)
  }
}

///|
test "annotates a frame present in both profiles" {
  let tree = diff_of("root;a 100", "root;a 150")
  let root = tree.roots[0]
  assert_eq(delta_of(root), 50.0)
  assert_eq(delta_of(child_named(root, "a")), 50.0)
}

///|
test "annotates a frame that only exists in the current profile" {
  // 基线里没有这个帧，变化量就等于它现在的全部权重
  let tree = diff_of("root;a 100", "root;a 100\nroot;b 40")
  let root = tree.roots[0]
  assert_eq(delta_of(child_named(root, "b")), 40.0)
}

///|
test "drops frames that only exist in the baseline" {
  // 宽度按当前剖面走，消失的帧不显示——这是与参考实现一致的取舍
  let tree = diff_of("root;a 100\nroot;gone 50", "root;a 100")
  let root = tree.roots[0]
  assert_true(root.child("gone") is None)
  assert_eq(root.value, 100.0)
}

///|
test "records a negative delta when a frame shrank" {
  // 这正是"优化有效"的情形：变少 → 蓝
  let tree = diff_of("root;hot 100", "root;hot 25")
  let root = tree.roots[0]
  assert_eq(delta_of(child_named(root, "hot")), -75.0)
}

///|
test "reports the largest absolute delta for colour scaling" {
  let tree = diff_of("root;a 100\nroot;b 100", "root;a 200\nroot;b 90")
  // a 涨了 100，b 跌了 10 → 最大变化量是 100
  assert_eq(tree.max_delta(), 100.0)
}

///|
test "leaves deltas unset in a normal tree" {
  let tree = tree_of("root;a 100", 0)
  assert_true(tree.roots[0].delta is None)
  assert_eq(tree.max_delta(), 0.0)
}

///|
test "propagates through the depth cap" {
  // 两份剖面都限深，会在同样的位置生成 (deeper)，其变化量照常累加
  let before = tree_of("root;a;b;c;d 100", 2)
  let after = tree_of("root;a;b;c;d 250", 2)
  let tree = @moonflame.diff_against(after, before)
  let root = tree.roots[0]
  let deeper = child_named(
    child_named(root, "a"),
    @moonflame.deeper_placeholder(),
  )
  assert_eq(delta_of(deeper), 150.0)
}

///|
test "colours growth red and shrinkage blue" {
  let layout = @moonflame.layout(
    diff_of("root;worse 100\nroot;better 100", "root;worse 200\nroot;better 50"),
    400.0,
    20.0,
  )
  let worse = find_rect(layout.rects, "worse")
  let better = find_rect(layout.rects, "better")
  match worse.delta {
    Some(value) =>
      assert_true(
        @moonflame.fill_for_delta(value, layout.max_delta).contains("hsl(0,"),
      )
    None => fail("expected a delta")
  }
  match better.delta {
    Some(value) =>
      assert_true(
        @moonflame.fill_for_delta(value, layout.max_delta).contains("hsl(214,"),
      )
    None => fail("expected a delta")
  }
}

///|
test "uses a neutral colour for a negligible change" {
  assert_eq(@moonflame.fill_for_delta(0.0, 100.0), "hsl(0,0%,93%)")
  assert_eq(@moonflame.fill_for_delta(1.0, 1000.0), "hsl(0,0%,93%)")
}

///|
test "scales colour depth with the size of the change" {
  let slight = @moonflame.fill_for_delta(10.0, 100.0)
  let severe = @moonflame.fill_for_delta(100.0, 100.0)
  // 变化越大，颜色越深（亮度越低），两者不应相同
  assert_true(slight != severe)
}

///|
test "shows the delta in the hover title" {
  let layout = @moonflame.layout(
    diff_of("root;hot 100", "root;hot 400"),
    800.0,
    20.0,
  )
  let svg = @moonflame.render_svg(layout)
  assert_true(svg.contains("+300"))
  // 普通模式不带变化量
  let plain = @moonflame.render_svg(
    @moonflame.layout(tree_of("root;hot 400", 0), 800.0, 20.0),
  )
  assert_true(!plain.contains("+300"))
}
