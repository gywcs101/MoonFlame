///|
fn rejects(f : () -> Unit raise) -> Unit raise {
  let failed = try {
    f()
    false
  } catch {
    InvalidWeight(_) | InvalidTree(_) | InvalidGeometry(_) => true
    _ => false
  }
  assert_true(failed)
}

///|
test "reject invalid direct samples and overflow, ignore zero samples" {
  for weight in [-1.0, 0.0 / 0.0, 1.0 / 0.0] {
    rejects(fn() raise { ignore(aggregate([{ frames: ["r"], weight, }])) })
  }
  rejects(fn() raise { ignore(aggregate([{ frames: [], weight: 1.0, }])) })
  rejects(fn() raise { ignore(aggregate([], max_depth=-1)) })
  rejects(fn() raise {
    ignore(
      aggregate([
        { frames: ["r"], weight: 1.0e308, },
        { frames: ["r"], weight: 1.0e308, },
      ]),
    )
  })
  let tree = aggregate([
    { frames: ["r"], weight: -0.0, },
    { frames: ["x"], weight: 0.0, },
  ])
  assert_eq(tree.roots.length(), 0)
}

///|
test "inconsistent trees cannot reach analysis or geometry" {
  let leaf : Node = {
    name: "x",
    value: 2.0,
    children: [],
    delta: None,
    self_delta: None,
  }
  let parent : Node = {
    name: "r",
    value: 1.0,
    children: [leaf],
    delta: None,
    self_delta: None,
  }
  let bad : CallTree = { roots: [parent], total: 1.0, }
  rejects(fn() raise { ignore(layout(bad, 100.0, 16.0)) })
  rejects(fn() raise { ignore(diff_against(bad, bad)) })
  rejects(fn() raise { ignore(top_hotspots(bad, 10)) })
  rejects(fn() raise { ignore(find_callers(bad, "x")) })
  rejects(fn() raise { ignore(compute_delta(bad, bad, 10)) })
  rejects(fn() raise { validate_tree({ roots: [leaf], total: 1.0, }) })
}

///|
test "geometry rejects invalid dimensions and manually corrupted rectangles" {
  let tree = aggregate(parse_folded("r;x 1").samples)
  for value in [-1.0, 0.0, 0.0 / 0.0, 1.0 / 0.0] {
    rejects(fn() raise { ignore(layout(tree, value, 16.0)) })
    rejects(fn() raise { ignore(layout(tree, 100.0, value)) })
  }
  let good = layout(tree, 100.0, 16.0)
  rejects(fn() raise { ignore(render_svg(good, min_width=-1.0)) })
  rejects(fn() raise { ignore(render_svg(good, font_size=0.0)) })
  let bad_rect = { ..good.rects[1], width: -1.0, }
  rejects(fn() raise {
    ignore(render_svg({ ..good, rects: [good.rects[0], bad_rect], }))
  })
  let gap = { ..good.rects[1], width: 99.0, }
  rejects(fn() raise {
    ignore(render_svg({ ..good, rects: [good.rects[0], gap], }))
  })
  let large = render_svg(layout(tree, 1.0e10, 16.0))
  assert_true(large.contains("10000000020"))
}

///|
test "decimal roundoff does not create negative geometry" {
  let tree = aggregate(parse_folded("r;a 0.1\nr;b 0.2\nr;c 0.3").samples)
  let l = layout(tree, 1000.0, 16.0)
  for r in l.rects {
    assert_true(r.width >= 0.0)
  }
  ignore(render_svg(l))
}

///|
test "signed percentages round symmetrically without negative zero" {
  assert_eq(format_percent(-0.5), "-50.0%")
  assert_eq(format_percent(-0.00001), "0.0%")
  assert_eq(format_percent(-0.9997), "-100.0%")
  assert_eq(format_weight(-0.001, Nanoseconds), "0 ns")
}
