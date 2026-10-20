# Third-party materials and fixture provenance

MoonFlame's original implementation and demo workload are licensed under the
root [MIT license](LICENSE). The upstream benchmark binary and materials derived
from it below retain Apache-2.0 attribution; the root MIT license does not replace
that license. A complete copy is distributed in
[LICENSES/Apache-2.0.txt](LICENSES/Apache-2.0.txt).

## moon-pprof and its benchmark sample

- Project: [mizchi/moon-pprof](https://github.com/mizchi/moon-pprof).
- Fixed revision: `bb91eaa8bf35df975b3e3d67b12965202cf5ed39`, recorded in the
  published `moon-pprof 0.1.3` crate's `.cargo_vcs_info.json`.
- Original sample:
  [docs/samples/main.wasm](https://github.com/mizchi/moon-pprof/blob/bb91eaa8bf35df975b3e3d67b12965202cf5ed39/docs/samples/main.wasm).
  Its Git blob ID is `cadc881dc741708eb917f921cf2b107b20fdd6c5`.
- Upstream license: Apache-2.0; both `LICENSE-APACHE` and `bench/LICENSE` at this
  revision contain the same license text, reproduced verbatim here. The tracked
  tree at this fixed revision has no NOTICE file, and no sample-specific copyright
  notice is attached to the copied binary. No upstream notice was removed.
- `testdata/official-sample.wasm` is an unmodified, byte-identical copy of that
  upstream binary. Its SHA-256 and the other fixture hashes are recorded in
  [testdata/SOURCES.json](testdata/SOURCES.json).
- `testdata/official-sample.pb.gz` is a locally generated profiling result of this
  upstream binary, not a file copied from upstream. The recorded development
  history uses `moon-pprof 0.1.3 profile --wasm-gc ... --out ...`.
- `testdata/stress-recursive.folded` is generated from that compressed profile by
  `moon-pprof 0.1.3 pprof2folded`. Repeating the conversion reproduces its SHA-256
  exactly. It retains the upstream benchmark function names. Both derived fixtures
  are distributed with the same Apache-2.0 attribution as the benchmark sample.

The profiles were introduced by MoonFlame commit
`f703348d26a11e363c476c037924f783ea5c6c98`; its historical
`docs/DATA-PIPELINE.md` records the sampling and conversion process. Sampling is
nondeterministic: the frozen profile is reproducible as an input, while a new
sampling run is not expected to produce identical sample weights.

## MoonFlame's own demonstration materials

- `demo/demo.mbt` is MoonFlame's MIT-licensed workload. The frozen current demo
  fixtures were introduced with workload changes in commit
  `1b7355fcb0baca6307e719d4e3caf9736c636675`.
- `testdata/demo.wasm` is the stored compiled workload; `testdata/demo.pb.gz` is
  its local profile, collected using `moon-pprof 0.1.3` and the documented
  `profile --wasm-gc ... --iterations 3 --out ...` workflow.
- `testdata/demo.folded` is the exact `pprof2folded` conversion of that frozen
  profile; its hash has been reverified. Using an Apache-licensed sampling tool
  does not by itself relicense this original workload or its generated data.
- `testdata/demo-baseline.folded` is a synthetic demonstration baseline: multiply
  weights of stacks containing `bubble__sort` by 3, those containing
  `build__strings` by 0.8, floor the result, and keep other weights unchanged.
  It is not an independently sampled before-profile.
- `examples/flame.svg` and `examples/flame-diff.svg` are rendered from these demo
  inputs by MoonFlame. Their PNG counterparts are browser rasterizations of the
  corresponding SVG, without third-party artwork. Regenerate them using
  `node tests/browser/test.cjs --update-examples` after building the native CLI.
- Rebuild and resample the workload with `demo/reproduce.ps1` or
  `demo/reproduce.sh`; both require `moon` and `moon-pprof` on PATH. Frozen data
  checks and deterministic baseline regeneration are in
  `python scripts/verify-fixtures.py`.

Historical compiler information: `moonc 0.10.14`, `moon 0.1.20260920`.
The sampling executable's installed Cargo metadata identifies package 0.1.3,
target `x86_64-pc-windows-gnu`. No claim is made that a new compiler or sampling
run reproduces the stored WASM bytes or profile weights.

## MoonBit core and runtime in compiled fixtures

The compiled WASM samples contain MoonBit library/runtime components in addition
to the workload. The installed toolchain's core LICENSE and runtime source
headers identify Apache-2.0, with the runtime attribution:

Copyright 2026 International Digital Economy Academy

Those components retain their Apache-2.0 terms and attribution; the MIT license
for MoonFlame's own workload does not replace them. The complete Apache license
copy above accompanies these binaries as well. Source reference:
[moonbitlang/core](https://github.com/moonbitlang/core); the historical compiler
version used for these fixtures is recorded above.

## Other references and dependencies

- [Brendan Gregg / FlameGraph](https://github.com/brendangregg/FlameGraph),
  CDDL-1.0: reference for folded-stack format, palette formulas and interaction
  semantics. MoonFlame's renderer and embedded JavaScript are independent
  implementations; no FlameGraph source file is bundled.
- [google/pprof](https://github.com/google/pprof), Apache-2.0: historical
  cross-check of sampled weights. No code or binary from it is bundled.
- `moonbitlang/x@0.4.45`, Apache-2.0, is resolved by MoonBit for executable IO
  and exit status. Its source is not vendored in this repository.
- Playwright is a development-only browser test dependency; it is not imported
  by the MoonBit library or embedded in generated SVG. Its license accompanies
  the npm package installation.

## Verification

`python scripts/verify-fixtures.py` checks stored fixture hashes, the bundled
Apache license hash, and the synthetic baseline rule. Optional
`--moon-pprof PATH` also reconverts both compressed profiles and compares bytes.
The provenance manifest and this document must be updated together if fixtures
are intentionally changed. They and the license copy must accompany any package
that redistributes the upstream sample or its derived fixtures.
