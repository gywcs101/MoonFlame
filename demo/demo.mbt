///|
/// 演示负载：多种典型算法的耗时对比，用于生成适合出图的火焰图样例数据。
///
/// 设计目标：
///   1) 避免深递归——深递归会把画布撑高却只填满很窄一条（见 walk_tree 注释）
///   2) 保留清晰的并列分支（图有形状）
///   3) 各分支宽度差异明显（一眼看出最慢的那块）
///   4) 各阶段耗时都远大于采样分辨率（实测循环密集时约 24ms）

///|
/// 冒泡排序：故意使用 O(n^2) 实现，作为图上最宽的分支
fn bubble_sort(data : Array[Int]) -> Int {
  let n = data.length()
  let mut swaps = 0
  for i = 0; i < n - 1; i = i + 1 {
    for j = 0; j < n - 1 - i; j = j + 1 {
      if data[j] > data[j + 1] {
        let tmp = data[j]
        data[j] = data[j + 1]
        data[j + 1] = tmp
        swaps = swaps + 1
      }
    }
  }
  swaps
}

///|
/// 插入排序：比冒泡快，作为同一分支下较窄的对照
fn insertion_sort(data : Array[Int]) -> Int {
  let n = data.length()
  let mut moves = 0
  for i = 1; i < n; i = i + 1 {
    let key = data[i]
    let mut j = i - 1
    while j >= 0 && data[j] > key {
      data[j + 1] = data[j]
      moves = moves + 1
      j = j - 1
    }
    data[j + 1] = key
  }
  moves
}

///|
fn bench_sorting(n : Int) -> Int {
  let data = Array::makei(n, fn(i) { i * 7919 % 10007 })
  let swaps = bubble_sort(data)
  let data2 = Array::makei(n, fn(i) { i * 104729 % 10007 })
  let moves = insertion_sort(data2)
  swaps + moves
}

///|
fn build_strings(n : Int) -> Int {
  let mut total = 0
  for i = 0; i < n; i = i + 1 {
    let s = "item" + i.to_string() + "-payload"
    total = total + s.length()
  }
  total
}

///|
fn scan_strings(n : Int) -> Int {
  let corpus = "the quick brown fox jumps over the lazy dog 0123456789"
  let mut hits = 0
  for i = 0; i < n; i = i + 1 {
    if corpus.contains("fox") {
      hits = hits + 1
    }
  }
  hits
}

///|
fn bench_strings(n : Int) -> Int {
  build_strings(n) + scan_strings(n * 4)
}

///|
/// 矩阵乘法（一维数组模拟），作为图上较窄的分支
fn matmul(n : Int) -> Int {
  let a = Array::makei(n * n, fn(i) { i % 7 })
  let b = Array::makei(n * n, fn(i) { i % 5 })
  let mut acc = 0
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      let mut s = 0
      for k = 0; k < n; k = k + 1 {
        s = s + a[i * n + k] * b[k * n + j]
      }
      acc = acc + s
    }
  }
  acc
}

///|
/// 递归段每个节点的基础循环轮数。只影响该阶段的耗时占比，不影响图形形状。
///
/// 取值由实测决定：需让本阶段占足够大的时间比例，否则它占据的顶部若干行
/// 会因时间占比太小而变窄——尾部行越窄，「上半空」的问题就越明显。
const TREE_WORK : Int = 20000

///|
/// 分支递归深度——控制图形高度的旋钮。
///
/// 图上最多出现 `TREE_DEPTH + 3` 行，取 9 使最深处（约 13 行）比其它阶段
/// （最深 9 行）多出三四层，既保持长宽比又不会出现贯穿大片空白的细尖刺。
const TREE_DEPTH : Int = 9

///|
/// 分支递归：**浅**但**调用密集**。
///
/// 刻意不使用单链深递归（如原先的 `fib(32)`）。那种形状的问题不在于深，
/// 而在于「只占极少时间却撑高整张画布」：实测原负载里 `fib` 仅占 3.8% 的
/// 时间，却让 71% 的行近乎空白。
///
/// 换成二叉展开后，**同一深度的所有节点宽度之和恒等于根节点宽度**，
/// 因此每一行都被填满；同时保持高频函数调用——采样密度依赖调用频率。
fn walk_tree(depth : Int, seed : Int) -> Int {
  let mut acc = 0
  let rounds = TREE_WORK + seed % 53
  for i = 0; i < rounds; i = i + 1 {
    // 每步都对累加器取模，避免上千个节点 × 数万轮累加后溢出 Int
    acc = (acc + i * 31 + seed) % 1009
  }
  if depth <= 0 {
    // 叶子：多算一点，让最底层的宽度有层次而不是整齐等宽
    acc + seed % 97
  } else {
    acc +
    walk_tree(depth - 1, (seed * 2 + 1) % 1013) +
    walk_tree(depth - 1, (seed * 3 + 2) % 1019)
  }
}

///|
fn bench_recursion(n : Int) -> Int {
  let mut acc = 0
  for i = 0; i < n; i = i + 1 {
    acc = acc + walk_tree(TREE_DEPTH, (i * 37 + 11) % 1009)
  }
  acc
}

///|
/// 顶层入口：四个阶段都会被采样到，各阶段耗时都远大于采样分辨率。
/// 返回值汇总为 checksum，避免编译器把整个计算优化掉。
pub fn run_workload() -> Int {
  let mut checksum = 0
  checksum = checksum + bench_sorting(3000)
  checksum = checksum + bench_strings(30000)
  checksum = checksum + matmul(80)
  checksum = checksum + bench_recursion(3)
  checksum
}
