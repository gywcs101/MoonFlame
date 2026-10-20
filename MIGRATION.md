# Migrating from 0.1.x to 0.2.0

`0.2.0` fixes profile correctness and the sample redistribution materials.

- `parse_folded` remains tolerant: `samples` holds valid rows; `skipped_lines`
  equals `diagnostics.length()`. Each diagnostic has a one-based `line` and a
  `ParseIssueKind`: missing weight, invalid number, non-finite or negative weight.
  Blank rows are ignored; zero and negative-zero weights are accepted but omitted
  by aggregation. Check diagnostics before treating a profile as complete.
- `aggregate`, `layout`, `render_svg`, `diff_against`, `top_hotspots`,
  `find_callers`, `find_callees`, `has_matching_frame` and `compute_delta` can
  raise `ValidationError`. Propagate errors with a `raise` signature, or catch
  `InvalidWeight`, `InvalidTree`, `InvalidGeometry`. Invalid input and numeric
  overflow are not silently repaired. See the tested README example.
- `Node.self_delta` records the change in own weight. Ordinary nodes have both
  delta fields unset. Layout's synthetic `(self)` uses this field, so a vanished
  baseline child no longer produces a false improvement in its parent's own work.
- The argument order remains `diff_against(current, baseline)`,
  `compute_delta(before, after, top)` and `filter_folded(text, pattern)`.
  Incorrect order in the old README has been corrected.
- Caller/callee values now represent sample coverage: a sample contributes once
  to a grouped entry even in self or mutual recursion. Entries may overlap, so
  their percentages need not sum to 100%. Grouping uses original full names;
  normalization is for matching and display only.
- `render_relations` accepts optional `matched=true` to distinguish a matched leaf
  from an unknown query. The CLI supplies this using `has_matching_frame`.
- CLI invalid rows cause the whole command to fail, with no partial result and
  no opening/truncating of an existing output. Exit codes: 0 success/help/version,
  1 IO/profile/computation failure, 2 invalid arguments. Diagnostics go to stderr.
  A filter with zero matches succeeds and writes empty output, replacing any old
  file; rendering that empty output fails with no positive samples.
- Bad numeric arguments and unknown units are errors. Depth and top count must
  be nonnegative; zero means unlimited/all. Canvas width must exceed 20 px.
  `filter --max-depth` has been removed because it did nothing.
- SVG search percentages are relative to the current visible subtree; parent
  context and hidden frames are excluded. Narrow labels appear after zooming.
- Original code remains MIT. The copied upstream sample and its derived fixtures
  have explicit Apache-2.0 notices and a complete license copy in the package.

Core computations are checked on wasm, wasm-gc, JS and native. The supported
command-line streaming contract is tested on native, JS and WASI wasm. On the
installed 0.10.14 toolchain, builtin `eprintln` for wasm-gc falls back to stdout;
use the default native CLI (or JS/WASI wasm) for pipelines. This is a runtime
restriction, not a change to the portable library's four-backend support.
