# 开发约定

本仓库是 2026 MoonBit 黑客松参赛项目 **MoonFlame** 的代码仓库。

## 项目结构

- 仓库根目录即 MoonBit 模块根（`moon.mod` / `moon.pkg`）
- 每个包目录下必须有 `moon.pkg`
- 黑盒测试文件以 `_test.mbt` 结尾，白盒测试以 `_wbtest.mbt` 结尾
- `demo/` 是独立的 MoonBit 模块，仅用于生成演示样例数据

## 编码约定

- 每个代码块以 `///|` 开头，块内自成一体，便于独立重构
- 核心逻辑保持**纯函数**（输入 → 输出，不碰 IO / 时间 / 随机），IO 集中在 `cmd/main`
- 提交前运行 `moon info && moon fmt`，并检查 `.mbti` 差异是否符合预期
- 运行 `moon test`；涉及输出变化时用 `moon test --update` 刷新快照

## 防膨胀红线

1. 不新增第 2 个第三方依赖
2. 不做配置文件格式（要可配置就用命令行参数）
3. 命令行参数不超过 5 个
4. 不做 Web / 浏览器演示
5. 核心库超过 800 行即视为范围失控，回头砍功能
6. 只支持默认后端，不加条件编译

## Commit 约定

**提交信息一律使用英文**，遵循 [Conventional Commits](https://www.conventionalcommits.org/)：

```text
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

- 常用 type：`feat` / `fix` / `docs` / `test` / `refactor` / `perf` / `chore` / `ci`
- 描述用祈使句、小写开头、结尾不加句号，尽量控制在 50 字符以内
- 改动不直观时在 body 中说明「做了什么、为什么」（同样用英文）
- 关联 issue 时在 footer 写 `Closes #12`
- **禁止**为凑数而无意义拆分提交、空提交或重复提交

## AI 使用说明

本项目在开发过程中使用了 AI 辅助（代码草拟、文档整理、API 核对）。约定：

- AI 生成的代码必须**逐条通过测试验证**后才算完成，不以"看起来对"为准
- 关键结论（如采样分辨率、符号还原行为）必须来自**实测**，并记录在 `docs/DATA-PIPELINE.md`
- 与本仓库相关的技术判断均标注了依据来源

## 已知限制

见 `README.md` 的「已知限制」一节，以及 `docs/DATA-PIPELINE.md`（含上游工具的实测行为与环境踩坑记录）。
