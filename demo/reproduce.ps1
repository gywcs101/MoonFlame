#!/usr/bin/env pwsh
# 复现 demo 样例数据的完整流程：编译 wasm-gc → 采样 → 转折叠栈 → 热点概览
#
# 前置：moon-pprof 已安装（见其仓库说明）
# 用法（Windows PowerShell 5.1 与 PowerShell 7 都可以）：
#   powershell demo/reproduce.ps1
#   pwsh       demo/reproduce.ps1
#
# macOS / Linux 请用等价脚本：bash demo/reproduce.sh

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# 原生命令会把进度写到 stderr（moon 的 "Finished."、moon-pprof 的 "[profile]" 行）。
# 在 Windows PowerShell 5.1 下，stderr 会被折成 ErrorRecord，配合上面的
# $ErrorActionPreference='Stop' 会让脚本「明明跑完却以退出码 1 结束」。
# 因此这里把两个流合并，并改用 $LASTEXITCODE 判定每一步的成败。
function Invoke-Step {
    param([string]$Label, [scriptblock]$Command)
    Write-Host $Label -ForegroundColor Cyan
    # 只能在原生命令执行期间降级偏好：stderr 在重定向之前就已按 Stop 升级为终止错误，
    # 单靠 `2>&1` 拦不住。降级后改由 $LASTEXITCODE 判定成败。
    $ErrorActionPreference = 'Continue'
    & $Command 2>&1 | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) {
        throw "$Label 失败（退出码 $LASTEXITCODE）"
    }
}

# 把工作区内的 Rust 工具链（含 moon-pprof）挂到 PATH
$tcBin = Join-Path $root '_toolchain\cargo\bin'
if (Test-Path $tcBin) { $env:PATH = "$tcBin;E:\mingw64\bin;$env:PATH" }

if (-not (Get-Command moon-pprof -ErrorAction SilentlyContinue)) {
    Write-Error "找不到 moon-pprof。请先安装，或把它放到 PATH 上（安装方式见其仓库说明）。"
}

Push-Location $PSScriptRoot
try {
    Invoke-Step "[1/4] 编译 wasm-gc ..." { moon build --target wasm-gc }

    $wasm = "_build/wasm-gc/debug/build/cmd/main/main.wasm"
    if (-not (Test-Path $wasm)) { Write-Error "未找到 $wasm" }

    Invoke-Step "[2/4] 采样（3 轮）..." {
        moon-pprof profile --wasm-gc $wasm --iterations 3 --out demo.pb.gz
    }
    Invoke-Step "[3/4] 转折叠栈 ..." {
        moon-pprof pprof2folded demo.pb.gz demo.folded
    }
    Invoke-Step "[4/4] 热点概览 ..." {
        moon-pprof summary demo.pb.gz
    }

    Write-Host ""
    Write-Host "完成。生成 demo.folded（采样有随机性，每次行数与总耗时都会略有不同）。" -ForegroundColor Green
    Write-Host "渲染它：" -ForegroundColor Green
    Write-Host "  moon run cmd/main -- demo/demo.folded --out flame.svg" -ForegroundColor Green
    Write-Host "看文本热点（注意 --top 属于 hotspots 子命令）：" -ForegroundColor Green
    Write-Host "  moon run cmd/main -- hotspots demo/demo.folded --top 10" -ForegroundColor Green
} finally {
    Pop-Location
}
