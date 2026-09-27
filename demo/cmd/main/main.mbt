///|
/// 演示负载的入口。只做两件事：调用工作负载、打印校验和。
/// 打印是必要的——它保证计算不会被编译器优化掉。
fn main {
  println("checksum=\{@demo.run_workload()}")
}
