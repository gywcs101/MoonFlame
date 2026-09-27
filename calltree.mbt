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
} derive(Eq)

///|
/// 聚合结果。
pub struct CallTree {
  /// 根节点，已排序。格式允许出现多个根（如多线程采样），真实数据通常只有一个
  roots : Array[Node]
  /// 所有样本权重之和
  total : Double
} derive(Eq)

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
  { name, value: 0.0, children: Map([]) }
}

///|
/// 把一条样本的调用链插入树中，逐层「查找或创建」子节点并累加权重。
///
/// `index` 从 `frames` 的第几层开始插入。
fn insert_path(
  node : Builder,
  frames : Array[String],
  index : Int,
  weight : Double,
) -> Unit {
  node.value = node.value + weight
  if index >= frames.length() {
    return
  }
  let name = frames[index]
  let child = match node.children.get(name) {
    Some(existing) => existing
    None => {
      let created = Builder::new(name)
      node.children.set(name, created)
      created
    }
  }
  insert_path(child, frames, index + 1, weight)
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
  { name: self.name, value: self.value, children }
}

///|
/// 把样本聚合成调用树。
pub fn aggregate(samples : Array[Sample]) -> CallTree {
  // 虚拟入口：只作为插入起点，不进入结果，避免把「取或建」逻辑写两遍
  let entry = Builder::new("")
  let mut total = 0.0
  for sample in samples {
    insert_path(entry, sample.frames, 0, sample.weight)
    total = total + sample.weight
  }
  let roots : Array[Node] = []
  for pair in entry.children {
    roots.push(pair.1.materialize())
  }
  roots.sort_by(compare_nodes)
  { roots, total }
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
