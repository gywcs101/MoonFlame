///|
/// 文本报告：调用关系查询、差异排行、栈过滤。
///
/// 这些都是**文本形态**的分析能力，与出图互补：
/// 图适合「一眼看出大头在哪」，文本适合「精确回答某个函数的上下游是谁」。
/// 把它们做成子命令而不是渲染选项，顶层参数因此不会随功能增长而膨胀。

///|
/// 一条调用关系条目。
pub struct Relation {
  /// 可读的标签：callers 是祖先链，callees 是子函数名
  label : String
  /// 该条目的权重
  value : Double
  /// 占全图的比例
  ratio : Double
} derive(Eq)

///|
/// 按权重降序、同值按标签升序，保证输出确定。
fn compare_relations(a : Relation, b : Relation) -> Int {
  if a.value > b.value {
    -1
  } else if a.value < b.value {
    1
  } else {
    String::compare(a.label, b.label)
  }
}

///|
/// 查询匹配规则：两侧都先归一化名字，再按**子串**比对。
///
/// 用子串而不是全等，是因为真实数据里的节点名是 `moonflame::demo::walk__tree`
/// 这样的完整路径，要求用户一字不差地打全既累赘又容易错；
/// 归一化则让 `walk_tree` 和 `walk__tree` 两种写法都能命中。
fn matches_query(name : String, query : String) -> Bool {
  if query == "" {
    return false
  }
  normalize_name(name).contains(normalize_name(query))
}

///|
/// 深度优先遍历，按**直接调用者**聚合权重。
///
/// 只记直属父节点的名字、并把同一父节点的多次出现合并，而不是把每条完整
/// 调用链都列一行——递归函数会产生大量几乎相同的长链，全列出来反而看不出
/// 「到底是谁在调用它」。
fn collect_callers(
  node : Node,
  parent : String,
  wanted : String,
  acc : Map[String, Double],
) -> Unit {
  if matches_query(node.name, wanted) {
    // 自递归产生的边要被排除：那条边承载的权重就是本函数自己的子树，
    // 逐层累加会让同一段时间被重复计入，占比算出 369% 这种荒谬值。
    // 递归深度不改变「谁在调用它」这个问题的答案。
    let self_edge = parent != "" && matches_query(parent, wanted)
    if !self_edge {
      let label = if parent == "" { "(根帧)" } else { parent }
      let current = match acc.get(label) {
        Some(value) => value
        None => 0.0
      }
      acc.set(label, current + node.value)
    }
  }
  for child in node.children {
    collect_callers(child, node.name, wanted, acc)
  }
}

///|
/// 深度优先遍历，按**直接子函数名**聚合权重。
fn collect_callees(
  node : Node,
  wanted : String,
  acc : Map[String, Double],
) -> Unit {
  if matches_query(node.name, wanted) {
    for child in node.children {
      let current = match acc.get(child.name) {
        Some(value) => value
        None => 0.0
      }
      acc.set(child.name, current + child.value)
    }
  }
  for child in node.children {
    collect_callees(child, wanted, acc)
  }
}

///|
/// 把「名字 → 权重」的累加表转成排序好的条目列表。
fn relations_of(acc : Map[String, Double], total : Double) -> Array[Relation] {
  let out : Array[Relation] = []
  for pair in acc {
    out.push({
      label: pair.0,
      value: pair.1,
      ratio: if total > 0.0 {
        pair.1 / total
      } else {
        0.0
      },
    })
  }
  out.sort_by(compare_relations)
  out
}

///|
/// 查询「谁调用了这个函数」。按直接调用者聚合。
///
/// 同一个函数会在多条路径下被调用（例如 `array::Array::at` 既在冒泡排序里
/// 也在插入排序里被调用），因此返回的是一个列表而不是单条路径。
pub fn find_callers(tree : CallTree, wanted : String) -> Array[Relation] {
  let acc : Map[String, Double] = Map([])
  for root in tree.roots {
    collect_callers(root, "", wanted, acc)
  }
  relations_of(acc, tree.total)
}

///|
/// 查询「这个函数调用了谁」。按被调用者聚合。
pub fn find_callees(tree : CallTree, wanted : String) -> Array[Relation] {
  let acc : Map[String, Double] = Map([])
  for root in tree.roots {
    collect_callees(root, wanted, acc)
  }
  relations_of(acc, tree.total)
}

///|
/// 把调用关系渲染成文本。
pub fn render_relations(
  relations : Array[Relation],
  wanted : String,
  kind : String,
  unit : WeightUnit,
) -> String {
  let sb = StringBuilder()
  if relations.length() == 0 {
    sb.write_string("没有找到与「\{wanted}」匹配的帧。\n")
    return sb.to_string()
  }
  sb.write_string("\{kind}「\{wanted}」— 共 \{relations.length()} 项\n\n")
  sb.write_string("  占比       权重  调用链\n")
  for r in relations {
    sb.write_string(
      "  " +
      String::pad_start(format_percent(r.ratio), 6, ' ') +
      "  " +
      String::pad_start(format_weight(r.value, unit), 12, ' ') +
      "  " +
      r.label +
      "\n",
    )
  }
  sb.to_string()
}

///|
/// 一个函数在两份剖面之间的自身耗时变化。
pub struct DeltaEntry {
  name : String
  before : Double
  after : Double
  /// `after - before`，正数表示变慢了
  change : Double
  /// 变化量占基线总量的比例
  ratio : Double
} derive(Eq)

///|
/// 按变化量降序（变慢最多的在前），同值按名字升序。
fn compare_deltas(a : DeltaEntry, b : DeltaEntry) -> Int {
  if a.change > b.change {
    -1
  } else if a.change < b.change {
    1
  } else {
    String::compare(a.name, b.name)
  }
}

///|
/// 对比两份剖面的**自身耗时**，按函数名对齐。
///
/// 只出现在其中一侧的函数也会被列出（另一侧记 0），因为「新增的开销」
/// 和「消失的开销」恰恰是差异分析最关心的两件事。
///
/// `top <= 0` 表示不截断。
pub fn compute_delta(
  before : CallTree,
  after : CallTree,
  top : Int,
) -> Array[DeltaEntry] {
  let before_map : Map[String, Double] = Map([])
  for hotspot in top_hotspots(before, 0) {
    before_map.set(hotspot.name, hotspot.self_time)
  }
  let after_map : Map[String, Double] = Map([])
  for hotspot in top_hotspots(after, 0) {
    after_map.set(hotspot.name, hotspot.self_time)
  }
  let all : Array[DeltaEntry] = []
  let seen : Map[String, Bool] = Map([])
  for hotspot in top_hotspots(after, 0) {
    let name = hotspot.name
    seen.set(name, true)
    let previous = match before_map.get(name) {
      Some(value) => value
      None => 0.0
    }
    all.push({
      name,
      before: previous,
      after: hotspot.self_time,
      change: hotspot.self_time - previous,
      ratio: if before.total > 0.0 {
        (hotspot.self_time - previous) / before.total
      } else {
        0.0
      },
    })
  }
  for hotspot in top_hotspots(before, 0) {
    if seen.get(hotspot.name) is None {
      all.push({
        name: hotspot.name,
        before: hotspot.self_time,
        after: 0.0,
        change: -hotspot.self_time,
        ratio: if before.total > 0.0 {
          -hotspot.self_time / before.total
        } else {
          0.0
        },
      })
    }
  }
  all.sort_by(compare_deltas)
  let count = if top > 0 && top < all.length() { top } else { all.length() }
  let kept : Array[DeltaEntry] = []
  for i = 0; i < count; i = i + 1 {
    kept.push(all[i])
  }
  kept
}

///|
/// 把差异排行渲染成文本。
///
/// 与差异火焰图的分工：图看**结构**（哪条路径变宽了），
/// 这张表看**函数**（哪个函数的自身耗时变了多少）。
pub fn render_delta(
  entries : Array[DeltaEntry],
  before_total : Double,
  after_total : Double,
  unit : WeightUnit,
) -> String {
  let sb = StringBuilder()
  sb.write_string(
    "自身耗时变化（基线共 \{format_weight(before_total, unit)}，" +
    "当前共 \{format_weight(after_total, unit)}）\n",
  )
  sb.write_string("\n")
  if entries.length() == 0 {
    sb.write_string("两份剖面没有可比对的函数。\n")
    return sb.to_string()
  }
  sb.write_string("     变化        变化%  基线  当前  函数\n")
  for e in entries {
    sb.write_string(
      "  " +
      String::pad_start(format_signed_weights(e.change, unit), 12, ' ') +
      "  " +
      String::pad_start(format_percent(e.ratio), 7, ' ') +
      "  " +
      String::pad_start(format_weight(e.before, unit), 11, ' ') +
      "  " +
      String::pad_start(format_weight(e.after, unit), 11, ' ') +
      "  " +
      e.name +
      "\n",
    )
  }
  sb.to_string()
}

///|
/// 取出折叠栈行里的「栈」部分（丢掉末尾的权重）。
///
/// 不用「找最后一个空格再切」的写法：名字里可能含多字节字符，
/// 按字符下标切片容易切错字节边界。按空格拆开再拼回去没有这个问题。
fn stack_part(line : String) -> String {
  let parts : Array[String] = []
  for piece in line.split(" ") {
    parts.push(piece.to_owned())
  }
  if parts.length() <= 1 {
    return line
  }
  let head : Array[String] = []
  for i = 0; i < parts.length() - 1; i = i + 1 {
    head.push(parts[i])
  }
  head.join(" ")
}

///|
/// 对整条栈逐帧做名字归一化。
///
/// 不能把整串丢给 `normalize_name`：那个函数是按**单个帧名**设计的，
/// 而栈串以 `____moonbit__main` 开头，会命中「下划线开头不折叠」的保护规则，
/// 结果整条栈一个下划线都折不了。
fn normalized_stack(stack : String) -> String {
  let parts : Array[String] = []
  for frame in stack.split(";") {
    parts.push(normalize_name(frame.to_owned()))
  }
  parts.join(";")
}

///|
/// 按子串过滤折叠栈：只保留调用链里含该子串的行。
///
/// 这是经典的 `grep funcA input | flamegraph.pl` 用法，但省掉了管道——
/// 过滤后的结果仍是折叠栈格式，可以直接再喂给出图命令。
///
/// 匹配前做名字归一化，否则用户按可读名 `build_strings` 去筛，
/// 会一条都筛不到（数据里存的是 `build__strings`）。
///
/// 权重原样保留、不做归一化：过滤后的图回答的是「这个子系统内部怎么分配时间」，
/// 而它占全局多少，靠保留原始权重才能在两张图之间对照。
pub fn filter_folded(text : String, pattern : String) -> String {
  let wanted = normalize_name(pattern)
  let sb = StringBuilder()
  for raw in text.split("\n") {
    let line = raw.trim().to_owned()
    if line == "" {
      continue
    }
    // 只匹配栈部分，免得像 "42" 这样的模式误命中权重数字
    if wanted != "" && normalized_stack(stack_part(line)).contains(wanted) {
      sb.write_string(line)
      sb.write_string("\n")
    }
  }
  sb.to_string()
}
