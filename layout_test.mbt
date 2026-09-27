///|
/// 黑盒测试：布局计算。
///
/// 核心不变量：**每个有子项的矩形，其子项宽度之和必须精确等于它自己的宽度**。
/// 这条性质同时保证了「按比例切分」和「最后一个子项顶父边界」两件事做对了——
/// 少了后者，几千个矩形之后就会出现肉眼可见的缝或重叠。

///|
/// 找出所属层级紧随其下、且落在 `parent` 水平范围内的矩形。
fn children_of(
  rects : Array[@moonflame.Rect],
  parent : @moonflame.Rect,
) -> Array[@moonflame.Rect] {
  let out : Array[@moonflame.Rect] = []
  for rect in rects {
    if rect.depth == parent.depth + 1 &&
      rect.x >= parent.x - 1.0e-9 &&
      rect.x + rect.width <= parent.x + parent.width + 1.0e-9 {
      out.push(rect)
    }
  }
  out
}

///|
/// 检查每个矩形是否被其子项精确覆盖。
fn coverage_problems(rects : Array[@moonflame.Rect]) -> Array[String] {
  let out : Array[String] = []
  for parent in rects {
    let kids = children_of(rects, parent)
    if kids.length() > 0 {
      let mut sum = 0.0
      for kid in kids {
        sum = sum + kid.width
      }
      if sum - parent.width > 1.0e-6 {
        out.push(
          "children of " +
          parent.name +
          " cover " +
          sum.to_string() +
          " but parent spans " +
          parent.width.to_string(),
        )
      }
    }
  }
  out
}

///|
fn assert_covered(rects : Array[@moonflame.Rect]) -> Unit raise {
  let problems = coverage_problems(rects)
  if problems.length() > 0 {
    fail(problems.join(" | "))
  }
}

///|
test "places a single root across the full width" {
  let l = @moonflame.layout(tree_of("main;fft 100", 0), 800.0, 20.0)
  assert_eq(l.rects.length(), 2)
  let main = find_rect(l.rects, "main")
  assert_eq(main.x, 0.0)
  assert_eq(main.width, 800.0)
  assert_eq(main.y, 0.0)
  assert_eq(main.depth, 0)
}

///|
test "maps depth to the vertical axis" {
  let l = @moonflame.layout(tree_of("a;b;c 100", 0), 100.0, 15.0)
  assert_eq(find_rect(l.rects, "a").y, 0.0)
  assert_eq(find_rect(l.rects, "b").y, 15.0)
  assert_eq(find_rect(l.rects, "c").y, 30.0)
  assert_eq(l.max_depth, 2)
  assert_eq(l.row_count(), 3)
  assert_eq(l.height(), 45.0)
}

///|
test "splits children proportionally" {
  let l = @moonflame.layout(tree_of("root;a 75\nroot;b 25", 0), 400.0, 10.0)
  let a = find_rect(l.rects, "a")
  let b = find_rect(l.rects, "b")
  assert_eq(a.x, 0.0)
  assert_eq(a.width, 300.0)
  assert_eq(b.x, 300.0)
  assert_eq(b.width, 100.0)
  assert_covered(l.rects)
}

///|
test "orders children by value" {
  let l = @moonflame.layout(
    tree_of("root;small 10\nroot;big 90", 0),
    100.0,
    10.0,
  )
  let big = find_rect(l.rects, "big")
  assert_eq(big.x, 0.0)
  assert_eq(big.width, 90.0)
}

///|
test "adds a self rect only when a frame has children and its own time" {
  let l = @moonflame.layout(
    tree_of("main;compute;fft 900\nmain;compute 100", 0),
    1000.0,
    10.0,
  )
  let compute = find_rect(l.rects, "compute")
  assert_eq(compute.width, 1000.0)
  // fft 占 900，compute 自身 100
  assert_eq(find_rect(l.rects, "fft").width, 900.0)
  assert_eq(find_rect(l.rects, @moonflame.self_placeholder()).width, 100.0)
  assert_covered(l.rects)
}

///|
test "does not nest a self rect inside a leaf" {
  // 叶节点整块宽度就是它自己的耗时，不该再多套一层
  let l = @moonflame.layout(tree_of("main;fft 100", 0), 100.0, 10.0)
  assert_eq(l.rects.length(), 2)
  assert_eq(l.max_depth, 1)
  assert_true(find_rect(l.rects, "fft").width == 100.0)
}

///|
test "does not drift with many children" {
  // 97 个等值子节点：每个 1/97，浮点下最容易累积误差
  let parts : Array[String] = []
  for i = 0; i < 97; i = i + 1 {
    parts.push("root;c" + i.to_string() + " 1")
  }
  let l = @moonflame.layout(tree_of(parts.join("\n"), 0), 1000.0, 20.0)
  let root = find_rect(l.rects, "root")
  assert_eq(root.width, 1000.0)
  // 首个子项从左边界开始
  let kids = children_of(l.rects, root)
  assert_eq(kids.length(), 97)
  assert_eq(kids[0].x, 0.0)
  // 末个子项精确顶到右边界
  let last = kids[kids.length() - 1]
  assert_eq(last.x + last.width, 1000.0)
  assert_covered(l.rects)
}

///|
test "splits multiple roots proportionally" {
  let l = @moonflame.layout(tree_of("alpha 30\nbeta 70", 0), 1000.0, 10.0)
  assert_eq(l.rects.length(), 2)
  // 树中根按值降序，beta 在前
  let beta = find_rect(l.rects, "beta")
  let alpha = find_rect(l.rects, "alpha")
  assert_eq(beta.x, 0.0)
  assert_eq(beta.width, 700.0)
  assert_eq(alpha.x, 700.0)
  assert_eq(alpha.width, 300.0)
}

///|
test "handles empty input" {
  let l = @moonflame.layout(tree_of("", 0), 800.0, 20.0)
  assert_eq(l.rects.length(), 0)
  assert_eq(l.row_count(), 0)
  assert_eq(l.height(), 0.0)
}

///|
test "lays out a capped deep tree" {
  // 7254 层限深到 32：应当得到 33 行（32 层 + 一个 (deeper)）
  let recursion = Array::make(7253, "mizchi::bench::ackermann").join(";")
  let text = "____moonbit__main;" + recursion + " 3182800"
  let l = @moonflame.layout(tree_of(text, 32), 1200.0, 16.0)
  assert_eq(l.row_count(), 33)
  assert_eq(find_rect(l.rects, "____moonbit__main").width, 1200.0)
  assert_covered(l.rects)
}

///|
test "covers every parent on the real sample excerpt" {
  let text = "____moonbit__main;moonflame4demo13run__workload;moonflame::demo::matmul 3009200\n" +
    "____moonbit__main;moonflame4demo13run__workload;moonflame::demo::matmul;array::Array::at 5707200\n" +
    "____moonbit__main;moonflame4demo13run__workload;moonflame::demo::bench__sorting;moonflame::demo::bubble__sort 35055400\n" +
    "____moonbit__main;moonflame4demo13run__workload;moonflame::demo::bench__sorting;moonflame::demo::insertion__sort 26714300\n" +
    "____moonbit__main;moonflame4demo13run__workload;moonflame::demo::fib 1547200\n"
  for depth in [0, 2, 3, 4] {
    let l = @moonflame.layout(tree_of(text, depth), 1000.0, 20.0)
    assert_covered(l.rects)
  }
}
