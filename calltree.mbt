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
  /// Change in this frame's own weight, calculated before dropping baseline-only children.
  self_delta : Double?
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
  mut result : Node?
}

///|
fn Builder::new(name : String) -> Builder {
  { name, value: 0.0, children: Map([]), result: None, }
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
  let mut current = node
  current.value = current.value + weight
  for i = index; i < frames.length(); i = i + 1 {
    if max_depth > 0 && i >= max_depth {
      let deeper = child_of(current, deeper_placeholder())
      deeper.value = deeper.value + weight
      return
    }
    current = child_of(current, frames[i])
    current.value = current.value + weight
  }
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
  let pending : Array[(Builder, Bool)] = [(self, false)]
  while pending.length() > 0 {
    let (builder, visited) = pending[pending.length() - 1]
    ignore(pending.pop())
    if !visited {
      pending.push((builder, true))
      for pair in builder.children {
        pending.push((pair.1, false))
      }
    } else {
      let children : Array[Node] = []
      for pair in builder.children {
        if pair.1.result is Some(child) {
          children.push(child)
        }
      }
      children.sort_by(compare_nodes)
      builder.result = Some({
        name: builder.name,
        value: builder.value,
        children,
        delta: None,
        self_delta: None,
      })
    }
  }
  match self.result {
    Some(node) => node
    None => abort("materialization failed")
  }
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
  // Flatten first, then rebuild bottom-up without recursive host calls.
  let flat : Array[(Node, Node?, Int)] = []
  let pending : Array[(Node, Node?, Int)] = []
  let baseline_index = index_by_name(baseline)
  for i = nodes.length() - 1; i >= 0; i = i - 1 {
    pending.push((nodes[i], baseline_index.get(nodes[i].name), -1))
  }
  while pending.length() > 0 {
    let task = pending[pending.length() - 1]
    ignore(pending.pop())
    let (node, base, _) = task
    let idx = flat.length()
    flat.push(task)
    let base_children = match base {
      Some(other) => other.children
      None => []
    }
    let index = index_by_name(base_children)
    for i = node.children.length() - 1; i >= 0; i = i - 1 {
      let child = node.children[i]
      pending.push((child, index.get(child.name), idx))
    }
  }
  let children : Array[Array[Node]] = Array::makei(flat.length(), fn(_) { [] })
  let out : Array[Node] = []
  for i = flat.length() - 1; i >= 0; i = i - 1 {
    let (node, base, parent) = flat[i]
    let base_value = match base {
      Some(other) => other.value
      None => 0.0
    }
    let base_self = match base {
      Some(other) => other.self_time()
      None => 0.0
    }
    children[i].sort_by(compare_nodes)
    let annotated : Node = {
      name: node.name,
      value: node.value,
      children: children[i],
      delta: Some(node.value - base_value),
      self_delta: Some(node.self_time() - base_self),
    }
    if parent < 0 {
      out.push(annotated)
    } else {
      children[parent].push(annotated)
    }
  }
  out.sort_by(compare_nodes)
  out
}

///|
/// 把两份剖面叠加，给 `tree` 的每个节点标注相对 `baseline` 的变化量。
///
/// **宽度仍按 `tree`（当前剖面）计算**，因此只在基线里出现的帧不会显示——
/// 这与参考实现 `difffolded.pl` 的取舍一致（可交换两份文件再生成一张，
/// 从另一个方向看消失的帧）。
pub fn diff_against(
  tree : CallTree,
  baseline : CallTree,
) -> CallTree raise ValidationError {
  validate_tree(tree)
  validate_tree(baseline)
  { roots: annotate(tree.roots, baseline.roots), total: tree.total, }
}

///|
/// 树中最大的变化量绝对值，用于把差异配色归一化到同一量级。
///
/// 不做归一化的话，只要有一处剧变，其它所有变化在颜色上就全糊成一片。
pub fn CallTree::max_delta(self : CallTree) -> Double {
  let pending = self.roots.copy()
  let mut largest = 0.0
  while pending.length() > 0 {
    let node = pending[pending.length() - 1]
    ignore(pending.pop())
    for delta in [node.delta, node.self_delta] {
      if delta is Some(value) {
        largest = larger(largest, value.abs())
      }
    }
    for child in node.children {
      pending.push(child)
    }
  }
  largest
}

///|
/// 把样本聚合成调用树。
///
/// `max_depth` 限制每个根节点下保留的帧数：超出的部分会被合并进
/// `(deeper)` 合成节点（见 `insert_path`）。`max_depth = 0` 或不传表示不限制。
///
/// 真实采样数据里递归栈可达数千层（实测最深 7254 层），按每层一行渲染会得到
/// 十几万像素高的图，因此渲染前必须限深——这是 CLI 默认行为。
pub fn aggregate(
  samples : Array[Sample],
  max_depth? : Int,
) -> CallTree raise ValidationError {
  let limit = match max_depth {
    Some(depth) => depth
    None => 0
  }
  if limit < 0 {
    raise InvalidTree("max_depth must be nonnegative")
  }
  // 虚拟入口：只作为插入起点，不进入结果，避免把「取或建」逻辑写两遍
  let entry = Builder::new("")
  let mut total = 0.0
  for sample in samples {
    check_weight(sample.weight, "sample")
    if sample.frames.length() == 0 {
      raise InvalidTree("empty sample stack")
    }
    for name in sample.frames {
      if name == "" {
        raise InvalidTree("empty frame name")
      }
    }
    if sample.weight == 0.0 {
      continue
    }
    check_weight(total + sample.weight, "accumulated total")
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
  let own = self.value - children_total
  if own < 0.0 && own.abs() <= tolerance(self.value) {
    0.0
  } else {
    own
  }
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
