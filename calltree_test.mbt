///|
/// 黑盒测试：调用树聚合。
///
/// 重点覆盖两件事：**同父同名合并**的正确性，以及**排序的确定性**
/// （`Map` 顺序不稳，是最容易让输出抖动的坑）。

///|
test "aggregates a single sample" {
  let t = tree_of("main;compute;fft 100", 0)
  assert_eq(t.roots.length(), 1)
  assert_eq(t.total, 100.0)
  assert_eq(t.roots[0].name, "main")
  assert_eq(t.roots[0].value, 100.0)
}

///|
test "merges nodes sharing the same parent and name" {
  let t = tree_of(
    "main;compute;fft 100\nmain;compute;fft 50\nmain;compute;parse 30", 0,
  )
  assert_eq(t.total, 180.0)
  let main = t.roots[0]
  assert_eq(main.value, 180.0)
  guard main.child("compute") is Some(compute) else { fail("missing compute") }
  assert_eq(compute.value, 180.0)
  assert_eq(compute.children.length(), 2)
  guard compute.child("fft") is Some(fft) else { fail("missing fft") }
  assert_eq(fft.value, 150.0)
  guard compute.child("parse") is Some(parse) else { fail("missing parse") }
  assert_eq(parse.value, 30.0)
}

///|
test "keeps same-named frames under different parents separate" {
  // 同名但父节点不同，属于不同调用路径，不能合并
  let t = tree_of("main;a;x 10\nmain;b;x 20", 0)
  let main = t.roots[0]
  assert_eq(main.value, 30.0)
  guard main.child("a") is Some(a) else { fail("missing a") }
  guard main.child("b") is Some(b) else { fail("missing b") }
  assert_eq(a.value, 10.0)
  assert_eq(b.value, 20.0)
  guard a.child("x") is Some(ax) else { fail("missing a;x") }
  guard b.child("x") is Some(bx) else { fail("missing b;x") }
  assert_eq(ax.value, 10.0)
  assert_eq(bx.value, 20.0)
}

///|
test "sorts children by value descending" {
  let t = tree_of("main;small 10\nmain;big 100\nmain;mid 50", 0)
  let names = t.roots[0].children.map(fn(c) { c.name }).join(",")
  assert_eq(names, "big,mid,small")
}

///|
test "breaks value ties by name for determinism" {
  let t = tree_of("main;b 50\nmain;a 50", 0)
  let names = t.roots[0].children.map(fn(c) { c.name }).join(",")
  assert_eq(names, "a,b")
}

///|
test "sorts roots when several exist" {
  let t = tree_of("alpha;x 10\nbeta;y 20", 0)
  assert_eq(t.roots.length(), 2)
  assert_eq(t.total, 30.0)
  let names = t.roots.map(fn(r) { r.name }).join(",")
  assert_eq(names, "beta,alpha")
}

///|
test "produces an identical tree for identical input" {
  let text = "main;b;z 30\nmain;a 10\nmain;b;y 20\nother 5"
  assert_true(tree_of(text, 0) == tree_of(text, 0))
}

///|
test "computes self time as value minus children" {
  // compute 的 100 权重没有更深的帧，属于它自己消耗的时间
  let t = tree_of("main;compute;fft 900\nmain;compute 100", 0)
  let main = t.roots[0]
  guard main.child("compute") is Some(compute) else { fail("missing compute") }
  assert_eq(compute.value, 1000.0)
  assert_eq(compute.self_time(), 100.0)
  guard compute.child("fft") is Some(fft) else { fail("missing fft") }
  assert_eq(fft.self_time(), 900.0)
  // 根节点的时间全部被子节点覆盖，自身耗时为 0
  assert_eq(main.self_time(), 0.0)
}

///|
test "computes self ratio against the total" {
  let t = tree_of("main;compute;fft 900\nmain;compute 100", 0)
  let main = t.roots[0]
  guard main.child("compute") is Some(compute) else { fail("missing compute") }
  assert_eq(compute.self_ratio(t.total), 0.1)
}

///|
test "handles empty input" {
  let t = tree_of("", 0)
  assert_eq(t.roots.length(), 0)
  assert_eq(t.total, 0.0)
}

///|
test "aggregates real lines from testdata/demo.folded" {
  let text = "____moonbit__main;moonflame4demo13run__workload;moonflame::demo::matmul 3009200\n" +
    "____moonbit__main;moonflame4demo13run__workload;moonflame::demo::matmul;array::Array::at 5707200\n" +
    "____moonbit__main;moonflame4demo13run__workload;moonflame::demo::bench__sorting;moonflame::demo::bubble__sort 35055400\n"
  let t = tree_of(text, 0)
  assert_eq(t.total, 43771800.0)
  assert_eq(t.roots.length(), 1)
  let root = t.roots[0]
  assert_eq(root.name, "____moonbit__main")
  assert_eq(root.value, 43771800.0)
  // 未还原的 mangled 名照样参与合并
  guard root.child("moonflame4demo13run__workload") is Some(workload) else {
    fail("missing workload")
  }
  assert_eq(workload.value, 43771800.0)
  // bench__sorting 更宽，排在 matmul 前面
  let names = workload.children.map(fn(c) { c.name }).join(",")
  assert_eq(names, "moonflame::demo::bench__sorting,moonflame::demo::matmul")
}
