#!/usr/bin/env bash
# 复现 demo 样例数据的完整流程：编译 wasm-gc → 采样 → 转折叠栈 → 热点概览
#
# 与 demo/reproduce.ps1 等价，供 macOS / Linux 使用。
#
# 前置：
#   - MoonBit 工具链（moonc >= 0.10.14，见 README「环境要求」）
#   - moon-pprof（仅采集端需要，见其仓库说明）
#
# 用法：
#   bash demo/reproduce.sh

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"

# 工作区若自带 Rust 工具链（含 moon-pprof），优先用它
if [ -d "$root/_toolchain/cargo/bin" ]; then
  PATH="$root/_toolchain/cargo/bin:$PATH"
fi

if ! command -v moon-pprof >/dev/null 2>&1; then
  echo "错误：找不到 moon-pprof。" >&2
  echo "它只在「采集自己的程序」时需要；渲染器本身不需要。安装方式见其仓库说明。" >&2
  exit 1
fi

step() {
  local label="$1"
  shift
  echo "==> $label"
  "$@"
}

cd "$here"

step "[1/4] 编译 wasm-gc ..." moon build --target wasm-gc

wasm="_build/wasm-gc/debug/build/cmd/main/main.wasm"
if [ ! -f "$wasm" ]; then
  echo "错误：未找到 $wasm" >&2
  exit 1
fi

step "[2/4] 采样（3 轮）..." moon-pprof profile --wasm-gc "$wasm" --iterations 3 --out demo.pb.gz
step "[3/4] 转折叠栈 ..." moon-pprof pprof2folded demo.pb.gz demo.folded
step "[4/4] 热点概览 ..." moon-pprof summary demo.pb.gz

echo
echo "完成。生成 demo.folded（采样有随机性，每次行数与总耗时都会略有不同）。"
echo "渲染它："
echo "  moon run cmd/main -- demo/demo.folded --out flame.svg"
echo "看文本热点（注意 --top 属于 hotspots 子命令）："
echo "  moon run cmd/main -- hotspots demo/demo.folded --top 10"
