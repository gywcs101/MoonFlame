const fs = require('fs');
const path = 'D:/DSH项目/Moonbit黑客松/_probe_pprof/main.folded';
const text = fs.readFileSync(path, 'utf8');
const lines = text.split('\n').filter(l => l.trim().length > 0);

let total = 0;
let maxDepth = 0;
const depths = [];
const frames = new Map();
const stacks = [];
let badLines = 0;

for (const line of lines) {
  const sp = line.lastIndexOf(' ');
  if (sp <= 0) { badLines++; continue; }
  const stack = line.slice(0, sp);
  const value = Number(line.slice(sp + 1));
  if (!Number.isFinite(value)) { badLines++; continue; }
  total += value;
  const parts = stack.split(';');
  depths.push(parts.length);
  if (parts.length > maxDepth) maxDepth = parts.length;
  for (const p of parts) frames.set(p, (frames.get(p) || 0) + 1);
  stacks.push({ depth: parts.length, value, head: parts.slice(0, 3), tail: parts.slice(-2) });
}

depths.sort((a, b) => a - b);
const pct = (p) => depths[Math.min(depths.length - 1, Math.floor(depths.length * p))];

console.log('=== 文件 ===');
console.log('大小      :', (fs.statSync(path).size / 1048576).toFixed(2), 'MB');
console.log('行数(样本):', lines.length, '| 解析失败行:', badLines);
console.log('');
console.log('=== 值（第 2 列）===');
console.log('总和      :', total, '  → 若按纳秒计 =', (total / 1e6).toFixed(2), 'ms');
console.log('最大单行  :', Math.max(...stacks.map(s => s.value)));
console.log('最小单行  :', Math.min(...stacks.map(s => s.value)));
console.log('');
console.log('=== 栈深度（每行分号分段数）===');
console.log('最浅      :', depths[0]);
console.log('最深      :', maxDepth, '  ← 关键');
console.log('中位数    :', pct(0.5));
console.log('p90       :', pct(0.9));
console.log('p99       :', pct(0.99));
console.log('深度分布  :', JSON.stringify(
  Object.entries(depths.reduce((a, d) => { const k = d > 100 ? '>100' : String(d); a[k] = (a[k] || 0) + 1; return a; }, {}))
));
console.log('');
console.log('=== 出现过的不同帧名（' + frames.size + ' 个）===');
[...frames.entries()].sort((a, b) => b[1] - a[1]).slice(0, 20)
  .forEach(([n, c]) => console.log('  ' + String(c).padStart(5) + '×  ' + JSON.stringify(n)));
console.log('');
console.log('=== 按值排序 Top 8（栈只显示头尾）===');
stacks.sort((a, b) => b.value - a.value).slice(0, 8).forEach(s => {
  const head = s.head.join(' ; ');
  const tail = s.tail.join(' ; ');
  console.log('  ' + String(s.value).padStart(10) + '  depth=' + String(s.depth).padStart(5) +
    '  头[ ' + head + ' ]  …  尾[ ' + tail + ' ]');
});
