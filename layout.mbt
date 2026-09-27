///|
/// 布局：把调用树算成一组矩形坐标。
///
/// 采用 icicle 方向（根在顶部、逐层向下）。算法本身很简单，要点有三个：
///
///   1. **按值比例切分**：子项宽度 = 父宽度 × (子值 / 父值)。因此不需要任何
///      矩形打包算法，天然不重叠、不留缝；
///   2. **最后一个子项直接取父节点右边界**，而不是用累加值。否则浮点误差会
///      一点点累积，几千个矩形之后就会出现肉眼可见的缝或重叠；
///   3. **自身耗时作为合成子项参与切分**，这样「父宽 = 全部子项宽之和」严格成立，
///      图面上不会出现空洞。
///
/// 布局不做最小宽度过滤：它产出的是**精确**的几何数据，是否绘制小于若干像素的
/// 矩形属于渲染层的取舍。

///|
/// 一个待绘制的矩形。
pub struct Rect {
  x : Double
  /// 纵向位置。由 `layout` 在排布完成后统一确定：
  /// 火焰图方向下根在底部，因此 y 依赖整棵树的最大深度。
  mut y : Double
  width : Double
  height : Double
  name : String
  /// 累计权重；合成项（自身耗时）则为该帧的自身耗时
  value : Double
  depth : Int
  /// 差异模式下的变化量；普通模式下为 `None`
  delta : Double?
} derive(Eq)

///|
/// 布局结果。渲染器拿到的布局自带完整几何信息，无需再传画布参数。
pub struct Layout {
  rects : Array[Rect]
  /// 画布宽度，与传入值一致
  width : Double
  /// 每行高度，与传入值一致
  row_height : Double
  /// 最深的深度下标（渲染高度为 `(max_depth + 1) * row_height`）
  max_depth : Int
  /// 全部权重之和，用于计算占比
  total : Double
  /// 差异模式下最大的变化量绝对值，用于颜色归一化；非差异模式为 0
  max_delta : Double
  /// 纵向方向：`false` 火焰图（根在底部），`true` 冰柱图（根在顶部）。
  /// 交互脚本判断「祖先在上还是在下」时需要它。
  inverted : Bool
} derive(Eq)

///|
/// 「自身耗时」合成帧的名字。
pub fn self_placeholder() -> String {
  "(self)"
}

///|
/// 参与切分的一个子项：要么是真实子节点，要么是自身耗时的合成项。
priv struct Item {
  name : String
  value : Double
  node : Node?
}

///|
/// 排序规则：值降序；同值时按名字升序，保证确定性。
fn compare_items(a : Item, b : Item) -> Int {
  if a.value > b.value {
    -1
  } else if a.value < b.value {
    1
  } else {
    String::compare(a.name, b.name)
  }
}

///|
/// 布局一个节点的子树。`x0`/`x1` 是它占据的水平区间。
fn layout_node(
  node : Node,
  x0 : Double,
  x1 : Double,
  depth : Int,
  row_height : Double,
  rects : Array[Rect],
) -> Unit {
  let span = x1 - x0
  rects.push({
    x: x0,
    y: depth.to_double() * row_height,
    width: span,
    height: row_height,
    name: node.name,
    value: node.value,
    depth,
    delta: node.delta,
  })
  if span <= 0.0 || node.value <= 0.0 {
    return
  }
  // 子项 = 真实子节点 + 自身耗时合成项。
  // 两者之和恒等于 node.value，因此下面的比例切分不会留下空洞。
  //
  // 只有在**存在子节点**时才补合成项：叶节点的整块宽度本来就是它自己的耗时，
  // 再套一层 `(self)` 只会白白加深一层、徒增矩形。
  let items : Array[Item] = []
  for child in node.children {
    items.push({ name: child.name, value: child.value, node: Some(child) })
  }
  let own = node.self_time()
  if own > 0.0 && items.length() > 0 {
    items.push({ name: self_placeholder(), value: own, node: None })
  }
  // 自身耗时的变化量 = 本节点的变化量 − 子节点变化量之和。
  // 任一子节点没有变化量（非差异模式）时，合成项也不带变化量。
  let self_delta = match node.delta {
    Some(total) => {
      let mut sum = 0.0
      let mut complete = true
      for child in node.children {
        match child.delta {
          Some(value) => sum = sum + value
          None => complete = false
        }
      }
      if complete {
        Some(total - sum)
      } else {
        None
      }
    }
    None => None
  }
  items.sort_by(compare_items)
  let mut cursor = x0
  let mut index = 0
  for item in items {
    index = index + 1
    let next = if index == items.length() {
      // 最后一个子项直接顶到父节点右边界，消除浮点累加误差
      x1
    } else {
      cursor + span * (item.value / node.value)
    }
    match item.node {
      Some(child) =>
        layout_node(child, cursor, next, depth + 1, row_height, rects)
      None =>
        rects.push({
          x: cursor,
          y: (depth + 1).to_double() * row_height,
          width: next - cursor,
          height: row_height,
          name: item.name,
          value: item.value,
          depth: depth + 1,
          delta: self_delta,
        })
    }
    cursor = next
  }
}

///|
/// 把调用树布局成矩形列表（前序遍历顺序：父节点先于子节点）。
///
/// 多个根节点时按各自权重水平切分画布。
///
/// `inverted` 选择纵向方向：
///
///   - **默认（false）火焰图**：根在**底部**，逐层向上生长。底部密、顶部疏，
///     高耗时路径表现为向上伸出的「火苗」——这是 Brendan Gregg 定义的经典形态。
///   - `inverted = true` 冰柱图（icicle）：根在顶部，逐层向下。
///
/// 两种方向都只影响 y 坐标，水平切分完全一致。
pub fn layout(
  tree : CallTree,
  width : Double,
  row_height : Double,
  inverted? : Bool,
) -> Layout {
  let flip = match inverted {
    Some(value) => value
    None => false
  }
  let rects : Array[Rect] = []
  if width > 0.0 &&
    row_height > 0.0 &&
    tree.total > 0.0 &&
    tree.roots.length() > 0 {
    let mut cursor = 0.0
    let mut index = 0
    for root in tree.roots {
      index = index + 1
      let next = if index == tree.roots.length() {
        width
      } else {
        cursor + width * (root.value / tree.total)
      }
      layout_node(root, cursor, next, 0, row_height, rects)
      cursor = next
    }
  }
  let mut max_depth = 0
  for rect in rects {
    if rect.depth > max_depth {
      max_depth = rect.depth
    }
  }
  // 方向直到这里才能确定：火焰图的根在底部，y 取决于整棵树的最大深度
  if !flip {
    for rect in rects {
      rect.y = (max_depth - rect.depth).to_double() * row_height
    }
  }
  // 差异配色需要一个统一的量级做归一化，否则一处剧变就会让其它差别看不出来
  let mut max_delta = 0.0
  for rect in rects {
    match rect.delta {
      Some(value) => {
        let magnitude = if value < 0.0 { -value } else { value }
        if magnitude > max_delta {
          max_delta = magnitude
        }
      }
      None => ()
    }
  }
  {
    rects,
    width,
    row_height,
    max_depth,
    total: tree.total,
    max_delta,
    inverted: flip,
  }
}

///|
/// 需要绘制的行数（= 最深深度 + 1）。
pub fn Layout::row_count(self : Layout) -> Int {
  if self.rects.length() == 0 {
    0
  } else {
    self.max_depth + 1
  }
}

///|
/// 画布所需高度。
pub fn Layout::height(self : Layout) -> Double {
  self.row_count().to_double() * self.row_height
}
