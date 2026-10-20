///|
test "parser reports invalid rows with categories and source line numbers" {
  let parsed = @moonflame.parse_folded(
    "r 1\n\nr -1\nr NaN\nr Infinity\nr nope\nmissing\nr -0\nr 0",
  )
  assert_eq(parsed.samples.length(), 3)
  assert_eq(parsed.skipped_lines, 5)
  assert_eq(
    parsed.diagnostics.map(fn(x) { x.line.to_string() }).join(","),
    "3,4,5,6,7",
  )
  assert_true(parsed.diagnostics[0].kind is @moonflame.NegativeWeight)
  assert_true(parsed.diagnostics[1].kind is @moonflame.NonFiniteWeight)
  assert_true(parsed.diagnostics[2].kind is @moonflame.NonFiniteWeight)
  assert_true(parsed.diagnostics[3].kind is @moonflame.InvalidNumber)
  assert_true(parsed.diagnostics[4].kind is @moonflame.MissingWeight)
}

///|
test "deleted child does not change its parent's own delta" {
  let before = tree_of("r;gone 50\nr;keep 30\nr 20", 0)
  let after = tree_of("r;keep 30\nr 20", 0)
  let diff = @moonflame.diff_against(after, before)
  assert_true(diff.roots[0].delta == Some(-50.0))
  assert_true(diff.roots[0].self_delta == Some(0.0))
  let l = @moonflame.layout(diff, 1000.0, 16.0)
  assert_true(find_rect(l.rects, "(self)").delta == Some(0.0))
  let report = @moonflame.render_delta(
    @moonflame.compute_delta(before, after, 0),
    before.total,
    after.total,
    @moonflame.Count,
  )
  assert_true(report.contains("-50.0%"))
  assert_false(report.contains("-49.-9"))
}

///|
test "self and mutual recursion count sample coverage once" {
  let self_tree = tree_of("main;rec;rec;rec;leaf 100\nmain;rec 20", 0)
  let callers = @moonflame.find_callers(self_tree, "rec")
  assert_eq(value_of(callers, "main"), 120.0)
  assert_eq(value_of(callers, "rec"), 100.0)
  let callees = @moonflame.find_callees(self_tree, "rec")
  assert_eq(value_of(callees, "rec"), 100.0)
  let mutual = @moonflame.find_callers(tree_of("main;a;b;a;b;a 100", 0), "a")
  assert_eq(value_of(mutual, "b"), 100.0)
  for row in mutual {
    assert_true(row.ratio <= 1.0)
  }
  let broad = @moonflame.find_callers(
    tree_of("main;work_a;work_b 100", 0),
    "work",
  )
  assert_eq(value_of(broad, "work_a"), 100.0)
}

///|
test "unlimited 7254-frame pipeline and analysis use bounded host stack" {
  let text = Array::make(7254, "recursive").join(";") + " 1"
  let tree = tree_of(text, 0)
  let diff = @moonflame.diff_against(tree, tree)
  let l = @moonflame.layout(diff, 1000.0, 16.0)
  assert_eq(l.row_count(), 7254)
  assert_eq(@moonflame.top_hotspots(tree, 1)[0].self_time, 1.0)
  assert_eq(@moonflame.find_callees(tree, "recursive")[0].value, 1.0)
  assert_true(@moonflame.render_svg(l).contains("<g id=\"frames\">"))
}

///|
test "large time and count values do not overflow Int32" {
  assert_eq(
    @moonflame.format_weight(3000000000.0, @moonflame.Count),
    "3,000,000,000",
  )
  assert_eq(
    @moonflame.format_weight(30000000.0, @moonflame.Seconds),
    "30000000 s",
  )
}

///|
test "invalid tokens containing nan are not mislabeled nonfinite" {
  let parsed = @moonflame.parse_folded("r banana")
  assert_true(parsed.diagnostics[0].kind is @moonflame.InvalidNumber)
}
