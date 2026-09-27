///|
/// 黑盒测试：Top-N 热点报告。
///
/// 重点：**按函数名聚合**（同一函数在多条路径下的自身耗时必须合并），
/// 以及排序与截断的确定性。

///|
fn hotspots(text : String, top : Int) -> Array[@moonflame.Hotspot] {
  let tree = @moonflame.aggregate(@moonflame.parse_folded(text).samples)
  @moonflame.top_hotspots(tree, top)
}

///|
fn names(list : Array[@moonflame.Hotspot]) -> String {
  list.map(fn(h) { h.name }).join(",")
}

///|
test "ranks leaf functions by self time" {
  let list = hotspots("main;compute;fft 900\nmain;compute;parse 100", 10)
  assert_eq(names(list), "fft,parse")
  assert_eq(list[0].self_time, 900.0)
  assert_eq(list[0].ratio, 0.9)
  assert_eq(list[1].ratio, 0.1)
}

///|
test "aggregates one function across different call paths" {
  // a;leaf 与 b;leaf 是两条不同路径，但 leaf 自身是同一个函数
  let list = hotspots("main;a;leaf 10\nmain;b;leaf 30", 10)
  assert_eq(list.length(), 1)
  assert_eq(list[0].name, "leaf")
  assert_eq(list[0].self_time, 40.0)
  assert_eq(list[0].occurrences, 2)
  assert_eq(list[0].ratio, 1.0)
}

///|
test "counts an intermediate frame's own time" {
  // b 的 30 没有更深的帧，属于 b 自身消耗
  let list = hotspots("main;a;leaf 10\nmain;b 30", 10)
  assert_eq(names(list), "b,leaf")
  assert_eq(list[0].self_time, 30.0)
  assert_eq(list[0].occurrences, 1)
  assert_eq(list[1].self_time, 10.0)
}

///|
test "filters out pass-through frames with zero self time" {
  let list = hotspots("main;a;leaf 10", 10)
  assert_eq(names(list), "leaf")
}

///|
test "truncates to the requested number" {
  let list = hotspots("main;a 30\nmain;b 20\nmain;c 10", 2)
  assert_eq(names(list), "a,b")
  assert_eq(list.length(), 2)
}

///|
test "returns every entry when top is not positive" {
  let list = hotspots("main;a 30\nmain;b 20\nmain;c 10", 0)
  assert_eq(list.length(), 3)
  let all = hotspots("main;a 30\nmain;b 20\nmain;c 10", -1)
  assert_eq(all.length(), 3)
}

///|
test "breaks self time ties by name" {
  let list = hotspots("main;b 50\nmain;a 50", 10)
  assert_eq(names(list), "a,b")
}

///|
test "produces identical output for identical input" {
  let text = "main;b;z 30\nmain;a 10\nmain;b;y 20"
  assert_true(hotspots(text, 10) == hotspots(text, 10))
}

///|
test "handles an empty tree" {
  let list = hotspots("", 10)
  assert_eq(list.length(), 0)
}

///|
test "renders a text report" {
  let tree = @moonflame.aggregate(
    @moonflame.parse_folded("main;fft 900\nmain;parse 100").samples,
  )
  let report = @moonflame.render_hotspots(
    @moonflame.top_hotspots(tree, 10),
    tree.total,
  )
  assert_true(report.contains("Top 2 hotspots by self time (total 1000)"))
  assert_true(report.contains("90.0%"))
  assert_true(report.contains("10.0%"))
  assert_true(report.contains("fft"))
  assert_true(report.contains("parse"))
  // 标题 + 列表头 + 2 行数据 = 4 个非空行
  let lines = report.split("\n").to_array().filter(fn(l) { !l.is_blank() })
  assert_eq(lines.length(), 4)
}

///|
test "rounds a percentage up instead of truncating the fraction" {
  // 9997/10000 = 99.97% 应当进位成 100.0%，而不是 99.9%
  let tree = @moonflame.aggregate(
    @moonflame.parse_folded("main 9997\nother 3").samples,
  )
  let report = @moonflame.render_hotspots(
    @moonflame.top_hotspots(tree, 1),
    tree.total,
  )
  assert_true(report.contains("100.0%"))
}

///|
test "ranks real lines from testdata/demo.folded" {
  let text = "____moonbit__main;moonflame4demo13run__workload;moonflame::demo::matmul 3009200\n" +
    "____moonbit__main;moonflame4demo13run__workload;moonflame::demo::matmul;array::Array::at 5707200\n" +
    "____moonbit__main;moonflame4demo13run__workload;moonflame::demo::bench__sorting;moonflame::demo::bubble__sort 35055400\n"
  let list = hotspots(text, 10)
  // 根帧与中间帧自身耗时为 0，被过滤；剩下三个才是真正的热点
  assert_eq(
    names(list),
    "moonflame::demo::bubble__sort,array::Array::at,moonflame::demo::matmul",
  )
  assert_eq(list[0].self_time, 35055400.0)
  assert_eq(list[0].ratio, 35055400.0 / 43771800.0)
}
