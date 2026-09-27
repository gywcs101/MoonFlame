// 从真实剖面构造一份「优化前」的基线剖面，用于演示差异火焰图的另一个方向。
//
// 规则（刻意保持简单、可逐行复核）：
//   - 栈里含 `bubble__sort` 的行：权重 × 3      （模拟冒泡排序尚未优化时更慢）
//   - 栈里含 `build__strings` 的行：权重 × 0.8  （模拟字符串拼接已被优化）
//   - 其余行不变
// 权重向下取整为整数，与折叠栈格式一致。
//
// 这份基线是**构造**的，不是真实采样——README 与 docs/DATA-PIPELINE.md 均如此声明。
// 真实基线应当来自优化前的那次采样；这里只是为了让 diff 模式有一个可演示的输入。
//
// 用法: node tools/make-baseline.js <输入.folded> <输出.folded>

const fs = require('fs');

const [, , input, output] = process.argv;
if (!input || !output) {
  console.error('用法: node tools/make-baseline.js <输入.folded> <输出.folded>');
  process.exit(1);
}

const factor = (stack) => {
  if (stack.includes('bubble__sort')) return 3;
  if (stack.includes('build__strings')) return 0.8;
  return 1;
};

const out = fs
  .readFileSync(input, 'utf8')
  .split('\n')
  .filter((line) => line.trim())
  .map((line) => {
    const at = line.lastIndexOf(' ');
    const stack = line.slice(0, at);
    const weight = parseFloat(line.slice(at + 1));
    return `${stack} ${Math.floor(weight * factor(stack))}`;
  })
  .join('\n');

fs.writeFileSync(output, out + '\n');
console.log(`[make-baseline] ${out.split('\n').length} stacks -> ${output}`);
