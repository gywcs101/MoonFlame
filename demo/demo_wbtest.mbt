// 白盒测试：验证各算法实现的正确性。
// 工作负载的正确性会直接影响 checksum，进而影响 demo 数据的可复现性。

///|
test "bubble_sort 排序正确并统计交换次数" {
  let a = [3, 1, 2]
  let swaps = bubble_sort(a)
  assert_eq(a, [1, 2, 3])
  assert_eq(swaps, 2)
}

///|
test "bubble_sort 处理已有序数组（零交换）" {
  let a = [1, 2, 3, 4, 5]
  assert_eq(bubble_sort(a), 0)
  assert_eq(a, [1, 2, 3, 4, 5])
}

///|
test "insertion_sort 排序正确" {
  let a = [5, 2, 9, 1, 5, 6]
  let _ = insertion_sort(a)
  assert_eq(a, [1, 2, 5, 5, 6, 9])
}

///|
test "insertion_sort 处理空数组与单元素数组" {
  let empty : Array[Int] = []
  assert_eq(insertion_sort(empty), 0)
  let one = [42]
  assert_eq(insertion_sort(one), 0)
  assert_eq(one, [42])
}

///|
test "matmul 结果可复现" {
  assert_eq(matmul(4), matmul(4))
}

///|
test "walk_tree 结果确定，且在叶子处停止展开" {
  assert_eq(walk_tree(3, 5), walk_tree(3, 5))
  // 深度 <= 0 一律按叶子处理，不会无限递归
  assert_eq(walk_tree(0, 7), walk_tree(0, 7))
  assert_eq(walk_tree(-5, 7), walk_tree(0, 7))
  // 展开一层必然比叶子大：多出两个子树的贡献
  assert_true(walk_tree(1, 7) > walk_tree(0, 7))
}
