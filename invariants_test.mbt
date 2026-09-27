///|
/// 黑盒测试：调用树的结构不变量。
///
/// 这些性质在任何一次重构之后都必须成立，是布局阶段之前的最后一道防线。
/// 其中「子节点已排序」专门挡 `Map` 顺序泄漏导致的输出抖动——
/// 那类 bug 不会让程序崩溃，只会让图和报告时不时变个样，极难排查。

///|
/// 检查子节点是否按「value 降序，同值按 name 升序」排列。
fn children_sorted(children : Array[@moonflame.Node]) -> Bool {
  for i = 0; i + 1 < children.length(); i = i + 1 {
    let a = children[i]
    let b = children[i + 1]
    if a.value < b.value {
      return false
    }
    if a.value == b.value && String::compare(a.name, b.name) > 0 {
      return false
    }
  }
  true
}

///|
/// 递归收集一个节点子树中的所有不变量违规。
fn collect_problems(
  node : @moonflame.Node,
  path : String,
  out : Array[String],
) -> Unit {
  let here = if path == "" { node.name } else { path + ";" + node.name }
  if node.name == "" {
    out.push("empty frame name at <root>")
  }
  if node.self_time() < 0.0 {
    out.push("negative self time at " + here)
  }
  if !children_sorted(node.children) {
    out.push("children not sorted at " + here)
  }
  for child in node.children {
    if child.value > node.value {
      out.push("child wider than parent at " + here)
    }
    collect_problems(child, here, out)
  }
}

///|
/// 对一棵树做全面体检，返回所有违规描述。
fn problems_of(text : String, max_depth : Int) -> Array[String] {
  let tree = @moonflame.aggregate(
    @moonflame.parse_folded(text).samples,
    max_depth~,
  )
  let out : Array[String] = []
  let mut roots_total = 0.0
  for root in tree.roots {
    roots_total = roots_total + root.value
    collect_problems(root, "", out)
  }
  if roots_total != tree.total {
    out.push("sum of roots does not equal total")
  }
  if !children_sorted(tree.roots) {
    out.push("roots not sorted")
  }
  out
}

///|
/// 断言在给定输入与限深下不存在不变量违规；失败时打印具体违规内容。
fn assert_invariants(text : String, max_depth : Int) -> Unit raise {
  let problems = problems_of(text, max_depth)
  if problems.length() > 0 {
    fail("invariant violations: " + problems.join(" | "))
  }
}

///|
test "holds for a single chain" {
  assert_invariants("a;b;c;d 100", 0)
}

///|
test "holds for a wide tree" {
  assert_invariants("root;a 10\nroot;b 20\nroot;c 30\nroot;d 40", 0)
}

///|
test "holds for a forest" {
  assert_invariants("alpha;x 10\nbeta;y 20\ngamma;z 30", 0)
}

///|
test "holds for mixed stack depths" {
  let text = "a;b;c;d;e 100\na;b;c 50\na;b 25\na 5\nx;y 20\nx 10"
  assert_invariants(text, 0)
}

///|
test "holds at every depth limit" {
  let text = "a;b;c;d;e 100\na;b;c 50\na;b 25\na 5\nx;y 20"
  for depth in [0, 1, 2, 3, 4, 5, 99] {
    assert_invariants(text, depth)
  }
}

///|
test "holds for a deep synthetic tree" {
  // 100 层递进，每层一条栈：制造长链 + 分支的混合结构
  let sb = StringBuilder()
  let parts : Array[String] = []
  for i = 0; i < 100; i = i + 1 {
    parts.push("f" + i.to_string())
    sb.write_string(parts.join(";") + " " + (1000 - i).to_string() + "\n")
  }
  assert_invariants(sb.to_string(), 0)
  assert_invariants(sb.to_string(), 16)
  assert_invariants(sb.to_string(), 3)
}

///|
test "holds for equal weights" {
  // 全等权重会大量触发排序的 tie-break 分支
  assert_invariants("r;a 10\nr;b 10\nr;c 10\nr;d 10\nr;e 10", 0)
}

///|
test "holds for the real sample excerpt" {
  let text = "____moonbit__main;moonflame4demo13run__workload;moonflame::demo::matmul 3009200\n" +
    "____moonbit__main;moonflame4demo13run__workload;moonflame::demo::matmul;array::Array::at 5707200\n" +
    "____moonbit__main;moonflame4demo13run__workload;moonflame::demo::bench__sorting;moonflame::demo::bubble__sort 35055400\n" +
    "____moonbit__main;moonflame4demo13run__workload;moonflame::demo::bench__sorting;moonflame::demo::insertion__sort 26714300\n" +
    "____moonbit__main;moonflame4demo13run__workload;moonflame::demo::fib 1547200\n"
  for depth in [0, 1, 2, 3, 4] {
    assert_invariants(text, depth)
  }
}

///|
test "holds for empty input" {
  assert_invariants("", 0)
}
