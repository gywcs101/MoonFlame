///|
/// Invalid profiles and geometry are recoverable errors, including direct library input.
pub(all) suberror ValidationError {
  InvalidWeight(String)
  InvalidTree(String)
  InvalidGeometry(String)
}

///|
fn finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn tolerance(value : Double) -> Double {
  1.0e-12 * larger(1.0, value.abs())
}

///|
fn check_weight(value : Double, where_ : String) -> Unit raise ValidationError {
  if !finite(value) || value < 0.0 {
    raise InvalidWeight("\{where_}: weight must be finite and nonnegative")
  }
}

///|
/// Validate iteratively so that unlimited-depth profiles do not consume the host stack.
pub fn validate_tree(tree : CallTree) -> Unit raise ValidationError {
  check_weight(tree.total, "total")
  let pending : Array[Node] = []
  let mut sum = 0.0
  let root_names : Map[String, Bool] = Map([])
  for root in tree.roots {
    if root_names.contains(root.name) {
      raise InvalidTree("duplicate root name")
    }
    root_names.set(root.name, true)
    sum = sum + root.value
    pending.push(root)
  }
  if !finite(sum) || (sum - tree.total).abs() > tolerance(tree.total) {
    raise InvalidTree("root weights do not match total")
  }
  while pending.length() > 0 {
    let node = pending[pending.length() - 1]
    ignore(pending.pop())
    check_weight(node.value, node.name)
    if node.name == "" {
      raise InvalidTree("empty frame name")
    }
    let names : Map[String, Bool] = Map([])
    let mut children = 0.0
    for child in node.children {
      if names.contains(child.name) {
        raise InvalidTree("duplicate child name")
      }
      names.set(child.name, true)
      check_weight(child.value, child.name)
      children = children + child.value
      pending.push(child)
    }
    if !finite(children) || children - node.value > tolerance(node.value) {
      raise InvalidTree("children exceed parent: " + node.name)
    }
    for delta in [node.delta, node.self_delta] {
      if delta is Some(value) && !finite(value) {
        raise InvalidTree("non-finite difference")
      }
    }
  }
}

///|
fn positive_geometry(
  value : Double,
  name : String,
) -> Unit raise ValidationError {
  if !finite(value) || value <= 0.0 {
    raise InvalidGeometry(name + " must be finite and positive")
  }
}

///|
fn larger(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn smaller(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// Validate independently supplied layouts before serializing any SVG.
fn validate_layout(layout : Layout) -> Unit raise ValidationError {
  positive_geometry(layout.width, "width")
  positive_geometry(layout.row_height, "row_height")
  check_weight(layout.total, "layout total")
  check_weight(layout.max_delta, "max_delta")
  if layout.max_depth < 0 {
    raise InvalidGeometry("negative depth")
  }
  let path : Array[Int] = []
  let covered : Array[Double] = Array::make(layout.rects.length(), 0.0)
  let next_x : Array[Double] = Array::make(layout.rects.length(), 0.0)
  let mut root_right = 0.0
  let mut actual_depth = 0
  let mut root_value = 0.0
  for i = 0; i < layout.rects.length(); i = i + 1 {
    let r = layout.rects[i]
    check_weight(r.value, r.name)
    if !finite(r.x) ||
      !finite(r.y) ||
      !finite(r.width) ||
      !finite(r.height) ||
      r.x < 0.0 ||
      r.y < 0.0 ||
      r.width < 0.0 ||
      r.height < 0.0 ||
      r.depth < 0 ||
      !finite(r.x + r.width) ||
      r.x + r.width > layout.width + tolerance(layout.width) {
      raise InvalidGeometry("invalid rectangle: " + r.name)
    }
    if r.delta is Some(d) &&
      (!finite(d) || d.abs() > layout.max_delta + tolerance(layout.max_delta)) {
      raise InvalidGeometry("invalid delta scale")
    }
    let expected_y = (if layout.inverted {
        r.depth
      } else {
        layout.max_depth - r.depth
      }).to_double() *
      layout.row_height
    if r.depth > layout.max_depth ||
      (r.y - expected_y).abs() > tolerance(expected_y) ||
      (r.height - layout.row_height).abs() > tolerance(layout.row_height) {
      raise InvalidGeometry("invalid row geometry")
    }
    actual_depth = if r.depth > actual_depth { r.depth } else { actual_depth }
    while path.length() > 0 &&
          layout.rects[path[path.length() - 1]].depth >= r.depth {
      ignore(path.pop())
    }
    if r.depth == 0 {
      if (r.x - root_right).abs() > tolerance(layout.width) {
        raise InvalidGeometry("root gap or overlap")
      }
      root_right = r.x + r.width
      root_value = root_value + r.value
    } else {
      guard path.length() > 0 else { raise InvalidGeometry("missing parent") }
      let idx = path[path.length() - 1]
      let parent = layout.rects[idx]
      let expected_x = if covered[idx] == 0.0 { parent.x } else { next_x[idx] }
      if r.depth != parent.depth + 1 ||
        (r.x - expected_x).abs() > tolerance(layout.width) ||
        r.x + r.width > parent.x + parent.width + tolerance(layout.width) {
        raise InvalidGeometry("child gap, overlap or overflow")
      }
      covered[idx] = covered[idx] + r.width
      next_x[idx] = r.x + r.width
    }
    path.push(i)
  }
  for i = 0; i < covered.length(); i = i + 1 {
    if covered[i] > 0.0 &&
      (covered[i] - layout.rects[i].width).abs() > tolerance(layout.width) {
      raise InvalidGeometry("incomplete child coverage")
    }
  }
  if actual_depth != layout.max_depth ||
    (root_value - layout.total).abs() > tolerance(layout.total) ||
    (
      layout.rects.length() > 0 &&
      (root_right - layout.width).abs() > tolerance(layout.width)
    ) {
    raise InvalidGeometry("inconsistent layout totals")
  }
}
