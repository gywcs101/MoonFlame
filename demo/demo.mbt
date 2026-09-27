///|
/// 演示负载：多种典型算法的耗时对比，用于生成适合出图的火焰图样例数据。
///
/// 设计目标：
///   1) 避免深递归（防止出现数千层的病态栈）
///   2) 保留清晰的并列分支（图有形状）
///   3) 各分支宽度差异明显（一眼看出最慢的那块）
///   4) 总耗时约 1-2 秒（足够采到上千个样本）

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
/// 递归斐波那契：调用密集（非循环密集），用于检验采样密度与调用频率的关系
fn fib(n : Int) -> Int {
  if n < 2 {
    n
  } else {
    fib(n - 1) + fib(n - 2)
  }
}

///|
/// 顶层入口：四个阶段都会被采样到，各阶段耗时都远大于采样分辨率。
/// 返回值汇总为 checksum，避免编译器把整个计算优化掉。
pub fn run_workload() -> Int {
  let mut checksum = 0
  checksum = checksum + bench_sorting(3000)
  checksum = checksum + bench_strings(30000)
  checksum = checksum + matmul(80)
  checksum = checksum + fib(32)
  checksum
}
