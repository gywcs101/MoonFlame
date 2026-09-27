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
  y : Double
  width : Double
  height : Double
  name : String
  /// 累计权重；合成项（自身耗时）则为该帧的自身耗时
  value : Double
  depth : Int
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
        })
    }
    cursor = next
  }
}

///|
/// 把调用树布局成矩形列表（前序遍历顺序：父节点先于子节点）。
///
/// 多个根节点时按各自权重水平切分画布。
pub fn layout(tree : CallTree, width : Double, row_height : Double) -> Layout {
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
  { rects, width, row_height, max_depth, total: tree.total }
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
