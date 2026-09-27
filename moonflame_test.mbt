///|
/// 黑盒测试：只针对公开 API。

///|
test "version is exposed" {
  assert_eq(@moonflame.version(), "0.1.0")
}
