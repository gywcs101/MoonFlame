// MoonFlame 模块配置
// 参考：https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html

name = "gywcs101/moonflame"

version = "0.1.0"

import {
  // 仅命令行入口使用；核心库本身不依赖任何外部包。
  // moonbitlang/core 没有文件读写，CLI 需要它来读折叠栈、写 SVG。
  // 选 x 而不是 async：async 在 Windows 上要求 MSVC，而 MinGW 无法构建它。
  "moonbitlang/x@0.4.45",
}

preferred_target = "native"

readme = "README.md"

repository = "https://github.com/gywcs101/moonflame"

license = "Apache-2.0"

keywords = [ "flamegraph", "profiling", "visualization", "svg" ]

description = "Render folded stack profiles into interactive SVG flame graphs."
