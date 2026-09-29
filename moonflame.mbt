///|
/// MoonFlame：把折叠栈（folded stack）性能数据渲染成可交互的 SVG 火焰图。
///
/// 渲染管线由四个纯函数阶段组成，分别对应四个源文件：
///
///   1. `folded.mbt`   解析折叠栈文本
///   2. `calltree.mbt` 聚合成调用树、计算耗时、限深合并、差异标注
///   3. `layout.mbt`   按值比例切分矩形（火焰图 / 冰柱两种方向）
///   4. `svg.mbt`      渲染成自带交互脚本的 SVG
///
/// 另有 `hotspot.mbt` 输出文本版 Top-N 热点，`cli/` 负责参数解析，
/// `cmd/main/` 是唯一接触文件系统的入口包。

///|
/// 返回当前版本号，与 `moon.mod` 中的 `version` 保持一致。
///
/// ⚠️ 改版本号时有三处必须一起改，否则会出现「库里报 A、命令行报 B」：
///   1. `moon.mod` 的 `version`
///   2. 本函数的返回值
///   3. `cli/cli.mbt` 里传给命令行解析器的 `version=`
/// `moonflame_test.mbt` 会断言本函数的返回值，漏改会直接测试失败。
pub fn version() -> String {
  "0.1.1"
}
