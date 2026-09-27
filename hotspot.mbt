///|
/// Top-N 热点报告。
///
/// 火焰图里同一个函数会出现在多条不同的调用路径下（例如 `array::Array::at`
/// 既在冒泡排序里被调用，也在插入排序里被调用）。因此热点榜要**按函数名聚合**
/// 自身耗时，而不是逐节点罗列——这与 `go tool pprof -top`、`moon-pprof summary`
/// 的口径一致。
///
/// 权重单位是上游决定的（moon-pprof 输出纳秒），本模块不对单位做任何假设：
/// 占比始终有意义，绝对值原样展示。

///|
/// 一个热点条目：按函数名聚合后的自身耗时。
pub struct Hotspot {
  name : String
  /// 该函数在整棵树中的自身耗时合计
  self_time : Double
  /// 占全部权重的比例
  ratio : Double
  /// 在树中出现的节点数（被多少条不同路径调用）
  occurrences : Int
} derive(Eq)

///|
/// 聚合用的可变累加器。
priv struct Acc {
  mut self_time : Double
  mut occurrences : Int
}

///|
/// 深度优先遍历，按函数名累加自身耗时。
fn collect(node : Node, acc : Map[String, Acc]) -> Unit {
  let own = node.self_time()
  match acc.get(node.name) {
    Some(existing) => {
      existing.self_time = existing.self_time + own
      existing.occurrences = existing.occurrences + 1
    }
    None => acc.set(node.name, { self_time: own, occurrences: 1 })
  }
  for child in node.children {
    collect(child, acc)
  }
}

///|
/// 排序规则：自身耗时降序；同值时按名字升序，保证确定性。
fn compare_hotspots(a : Hotspot, b : Hotspot) -> Int {
  if a.self_time > b.self_time {
    -1
  } else if a.self_time < b.self_time {
    1
  } else {
    String::compare(a.name, b.name)
  }
}

///|
/// 取自身耗时最高的若干函数。
///
/// 自身耗时为 0 的函数是纯粹的「过路」节点，不构成热点，会被过滤掉
/// （与 `moon-pprof summary` 的口径一致）。
///
/// `top <= 0` 表示不截断，返回全部条目。
pub fn top_hotspots(tree : CallTree, top : Int) -> Array[Hotspot] {
  let acc : Map[String, Acc] = Map([])
  for root in tree.roots {
    collect(root, acc)
  }
  let all : Array[Hotspot] = []
  for pair in acc {
    let entry = pair.1
    if entry.self_time > 0.0 {
      all.push({
        name: pair.0,
        self_time: entry.self_time,
        ratio: if tree.total > 0.0 {
          entry.self_time / tree.total
        } else {
          0.0
        },
        occurrences: entry.occurrences,
      })
    }
  }
  all.sort_by(compare_hotspots)
  let count = if top > 0 && top < all.length() { top } else { all.length() }
  let kept : Array[Hotspot] = []
  for i = 0; i < count; i = i + 1 {
    kept.push(all[i])
  }
  kept
}

///|
/// 把比例格式化成一位小数的百分比。
///
/// 先放大成「千分比」再四舍五入，这样 99.97% 会正确进位成 100.0%，
/// 而不会出现 99.10% 这类结果。
fn format_percent(ratio : Double) -> String {
  let scaled = (ratio * 1000.0 + 0.5).to_int()
  let whole = scaled / 10
  let frac = scaled % 10
  "\{whole}.\{frac}%"
}

///|
/// 把热点列表渲染成纯文本报告。
///
/// `unit` 决定绝对值怎么显示（时间按数量级缩放，计数加千位分隔）；
/// 占比不受单位影响。
pub fn render_hotspots(
  hotspots : Array[Hotspot],
  total : Double,
  unit : WeightUnit,
) -> String {
  let sb = StringBuilder()
  sb.write_string(
    "Top \{hotspots.length()} hotspots by self time (total \{format_weight(total, unit)})\n",
  )
  sb.write_string("\n")
  sb.write_string("  #  self%       self time  frame\n")
  let mut rank = 0
  for h in hotspots {
    rank = rank + 1
    let rank_text = rank.to_string()
    let percent_text = format_percent(h.ratio)
    let weight_text = format_weight(h.self_time, unit)
    sb.write_string(
      String::pad_start(rank_text, 3, ' ') +
      "  " +
      String::pad_start(percent_text, 6, ' ') +
      "  " +
      String::pad_start(weight_text, 13, ' ') +
      "  " +
      h.name +
      "\n",
    )
  }
  sb.to_string()
}
