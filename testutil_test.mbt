///|
/// 测试共用的工具函数。
///
/// 黑盒测试文件同属一个包、共享顶层命名空间，所以公共 helper 只在这里定义一次。

///|
/// 从折叠栈文本构造调用树。
///
/// `max_depth <= 0` 表示不限制深度。
fn tree_of(text : String, max_depth : Int) -> @moonflame.CallTree {
  @moonflame.aggregate(@moonflame.parse_folded(text).samples, max_depth~)
}

///|
/// 按名字取出唯一匹配的矩形；找不到则让用例失败。
fn find_rect(
  rects : Array[@moonflame.Rect],
  name : String,
) -> @moonflame.Rect raise {
  let mut found : @moonflame.Rect? = None
  for rect in rects {
    if rect.name == name {
      found = Some(rect)
    }
  }
  match found {
    Some(rect) => rect
    None => fail("rect not found: " + name)
  }
}
