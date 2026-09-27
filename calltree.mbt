///|
/// 调用树的构建与表示。
///
/// 聚合刻意分两步：
///
///   1. **构建**：用可变、无序的 `Builder` 逐条样本插入，同父同名节点合并并累加权重；
///   2. **物化**：把 `Builder` 转成不可变、**已排序**的 `Node`。
///
/// 第二步不是多余的：`Map` 的遍历顺序不稳定，如果把 `Map` 直接暴露给渲染层，
/// 输出会随运行抖动、快照测试也会随机失败。排序键固定为
/// 「value 降序，同值按 name 升序」，保证同一份输入永远得到同一棵树。

///|
/// 调用树节点。`children` 已排序，可直接用于布局。
pub struct Node {
  name : String
  /// 累计权重，包含所有子节点
  value : Double
  /// 子节点：按 value 降序，同值按 name 升序
  children : Array[Node]
  /// 差异模式下的变化量（本剖面相对基线的差值）；普通模式下为 `None`
  delta : Double?
} derive(Eq)

///|
/// 显式声明 `Eq` 的两个方法可被当作常规方法调用。
///
/// 新版编译器（moonc 0.10.14 起）不再自动把 `impl Eq` 的方法提升为常规方法，
/// 不声明就会报 `implicit_impl_as_method` 废弃警告。这条声明把该提升写明，
/// 行为与过去一致；配合 CI 的「警告即失败」，也避免未来默认行为变更后突然失效。
pub extend Node with Eq::{not_equal, equal}

///|
/// 聚合结果。
pub struct CallTree {
  /// 根节点，已排序。格式允许出现多个根（如多线程采样），真实数据通常只有一个
  roots : Array[Node]
  /// 所有样本权重之和
  total : Double
} derive(Eq)

///|
/// 显式声明 `Eq` 的方法可被当作常规方法调用。
///
/// 新版编译器不再自动完成这个提升，不声明会报 `implicit_impl_as_method`。
pub extend CallTree with Eq::{not_equal, equal}

///|
/// 构建期的可变节点。
///
/// 只在聚合过程中存在：用 `Map` 便于「查找或创建」，顺序统一留到物化阶段处理。
priv struct Builder {
  name : String
  mut value : Double
  children : Map[String, Builder]
}

///|
fn Builder::new(name : String) -> Builder {
  { name, value: 0.0, children: Map([]), }
}

///|
/// 深度超限时，用来收纳「更深的帧」的合成节点名。
pub fn deeper_placeholder() -> String {
  "(deeper)"
}

///|
/// 取出子节点，不存在则创建。用 `Map` 便于按名字「查找或创建」。
fn child_of(node : Builder, name : String) -> Builder {
  match node.children.get(name) {
    Some(existing) => existing
    None => {
      let created = Builder::new(name)
      node.children.set(name, created)
      created
    }
  }
}

///|
/// 把一条样本的调用链插入树中，逐层「查找或创建」子节点并累加权重。
///
/// `index` 从 `frames` 的第几层开始插入；`max_depth > 0` 时限制保留的帧数。
///
/// **深度超限时不是丢弃，而是合并**：把 `frames[max_depth..]` 整段收纳进一个
/// 名为 `(deeper)` 的合成节点。两种做法的区别在归因：
///
///   - 丢弃：最后一个可见帧看起来「自己消耗」了下面所有的时间，是误导；
///   - 合并：多出一个显式的 `(deeper)` 子节点，诚实标出「下面还有更多」。
///
/// 两者都不破坏不变量 `自身耗时 ≥ 0`；合并只是不掩盖信息。
fn insert_path(
  node : Builder,
  frames : Array[String],
  index : Int,
  weight : Double,
  max_depth : Int,
) -> Unit {
  node.value = node.value + weight
  if index >= frames.length() {
    return
  }
  if max_depth > 0 && index >= max_depth {
    // 已经越过深度上限：把这一整段链的价值累加进合成节点，不再逐帧展开
    let deeper = child_of(node, deeper_placeholder())
    deeper.value = deeper.value + weight
    return
  }
  let child = child_of(node, frames[index])
  insert_path(child, frames, index + 1, weight, max_depth)
}

///|
/// 排序规则：value 降序；同值时按 name 升序，消除排序的不确定性。
fn compare_nodes(a : Node, b : Node) -> Int {
  if a.value > b.value {
    -1
  } else if a.value < b.value {
    1
  } else {
    String::compare(a.name, b.name)
  }
}

///|
/// 把构建期节点物化成不可变、已排序的 `Node`。
fn Builder::materialize(self : Builder) -> Node {
  let children : Array[Node] = []
  for pair in self.children {
    children.push(pair.1.materialize())
  }
  children.sort_by(compare_nodes)
  { name: self.name, value: self.value, children, delta: None, }
}

///|
/// 按名字给一层子节点建索引，用于两份剖面的对齐。
fn index_by_name(nodes : Array[Node]) -> Map[String, Node] {
  let index : Map[String, Node] = Map([])
  for node in nodes {
    index.set(node.name, node)
  }
  index
}

///|
/// 递归标注变化量：以 `baseline` 为基线，给 `nodes` 中每个节点算出差值。
fn annotate(nodes : Array[Node], baseline : Array[Node]) -> Array[Node] {
  let index = index_by_name(baseline)
  let out : Array[Node] = []
  for node in nodes {
    let matched = index.get(node.name)
    let base_value = match matched {
      Some(other) => other.value
      None => 0.0
    }
    let base_children = match matched {
      Some(other) => other.children
      None => []
    }
    out.push({
      name: node.name,
      value: node.value,
      delta: Some(node.value - base_value),
      children: annotate(node.children, base_children),
    })
  }
  out
}

///|
/// 把两份剖面叠加，给 `tree` 的每个节点标注相对 `baseline` 的变化量。
///
/// **宽度仍按 `tree`（当前剖面）计算**，因此只在基线里出现的帧不会显示——
/// 这与参考实现 `difffolded.pl` 的取舍一致（它的建议是交换两份文件再生成一张，
/// 从另一个方向看消失的帧）。
pub fn diff_against(tree : CallTree, baseline : CallTree) -> CallTree {
  { roots: annotate(tree.roots, baseline.roots), total: tree.total, }
}

///|
/// 树中最大的变化量绝对值，用于把差异配色归一化到同一量级。
///
/// 不做归一化的话，只要有一处剧变，其它所有变化在颜色上就全糊成一片。
pub fn CallTree::max_delta(self : CallTree) -> Double {
  let mut largest = 0.0
  for root in self.roots {
    let magnitude = max_delta_of(root)
    if magnitude > largest {
      largest = magnitude
    }
  }
  largest
}

///|
fn max_delta_of(node : Node) -> Double {
  let mut largest = match node.delta {
    Some(value) => if value < 0.0 { -value } else { value }
    None => 0.0
  }
  for child in node.children {
    let magnitude = max_delta_of(child)
    if magnitude > largest {
      largest = magnitude
    }
  }
  largest
}

///|
/// 把样本聚合成调用树。
///
/// `max_depth` 限制每个根节点下保留的帧数：超出的部分会被合并进
/// `(deeper)` 合成节点（见 `insert_path`）。`max_depth <= 0` 或不传表示不限制。
///
/// 真实采样数据里递归栈可达数千层（实测最深 7254 层），按每层一行渲染会得到
/// 十几万像素高的图，因此渲染前必须限深——这是 CLI 默认行为。
pub fn aggregate(samples : Array[Sample], max_depth? : Int) -> CallTree {
  let limit = match max_depth {
    Some(depth) => depth
    None => 0
  }
  // 虚拟入口：只作为插入起点，不进入结果，避免把「取或建」逻辑写两遍
  let entry = Builder::new("")
  let mut total = 0.0
  for sample in samples {
    insert_path(entry, sample.frames, 0, sample.weight, limit)
    total = total + sample.weight
  }
  let roots : Array[Node] = []
  for pair in entry.children {
    roots.push(pair.1.materialize())
  }
  roots.sort_by(compare_nodes)
  { roots, total, }
}

///|
/// 自身耗时：累计权重减去所有子节点累计权重之和。
///
/// 采样栈可能停在中间（例如 `main;compute 100` 表示这 100 的权重归 compute
/// 自己），此时该节点没有对应子节点，差额即它自身消耗的时间。
pub fn Node::self_time(self : Node) -> Double {
  let mut children_total = 0.0
  for child in self.children {
    children_total = children_total + child.value
  }
  self.value - children_total
}

///|
/// 按名字查找直接子节点。
pub fn Node::child(self : Node, name : String) -> Node? {
  for child in self.children {
    if child.name == name {
      return Some(child)
    }
  }
  None
}

///|
/// 自身耗时占给定总量的比例，用于文本报告与图上的百分比标注。
pub fn Node::self_ratio(self : Node, total : Double) -> Double {
  if total <= 0.0 {
    0.0
  } else {
    self.self_time() / total
  }
}
