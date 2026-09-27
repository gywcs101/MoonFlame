#!/usr/bin/env pwsh
# 复现 demo 样例数据的完整流程
#
# 前置：moon-pprof 已安装（见仓库根目录的 MoonFlame-数据链路验证报告.md）
# 用法（两种 Shell 都可以）：
#   pwsh   demo/reproduce.ps1
#   powershell demo/reproduce.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# 把工作区内的 Rust 工具链（含 moon-pprof）挂到 PATH
$tcBin = Join-Path $root '_toolchain\cargo\bin'
if (Test-Path $tcBin) { $env:PATH = "$tcBin;E:\mingw64\bin;$env:PATH" }

if (-not (Get-Command moon-pprof -ErrorAction SilentlyContinue)) {
    Write-Error "找不到 moon-pprof。请先按 MoonFlame-数据链路验证报告.md 安装，或把它放到 PATH 上。"
}

Push-Location $PSScriptRoot
try {
    Write-Host "[1/4] 编译 wasm-gc ..." -ForegroundColor Cyan
    moon build --target wasm-gc

    $wasm = "_build/wasm-gc/debug/build/cmd/main/main.wasm"
    if (-not (Test-Path $wasm)) { Write-Error "未找到 $wasm" }

    Write-Host "[2/4] 采样（3 轮）..." -ForegroundColor Cyan
    moon-pprof profile --wasm-gc $wasm --iterations 3 --out demo.pb.gz

    Write-Host "[3/4] 转折叠栈 ..." -ForegroundColor Cyan
    moon-pprof pprof2folded demo.pb.gz demo.folded

    Write-Host "[4/4] 热点概览 ..." -ForegroundColor Cyan
    moon-pprof summary demo.pb.gz

    Write-Host ""
    Write-Host "完成。生成 demo.folded，可复制到 testdata/ 或交给 moonflame 渲染。" -ForegroundColor Green
} finally {
    Pop-Location
}
