#!/usr/bin/env node
/**
 * check_topic.js — 选题撞车自查工具（MoonBit 黑客松选题用）
 *
 * 用法：
 *   node check_topic.js <关键词1> [关键词2] ...
 *       在本地缓存的 mooncakes.io 模块清单里检索关键词（不区分大小写，
 *       匹配 name + description + keywords），输出命中数与命中的模块列表。
 *
 *   node check_topic.js --refresh
 *       重新从 mooncakes.io 拉取全量模块清单并覆盖本地缓存。
 *
 *   node check_topic.js --all
 *       输出缓存中的模块总数与统计数据。
 *
 * 说明：命中数越低，说明该方向越可能是生态空白；命中数高说明已被实现，
 *       需要想清楚差异化理由（赛事规则要求"已有项目必须包含本期实质新增
 *       工作"，重复实现会被判定为无效工作）。
 */

const fs = require('fs');
const path = require('path');

const CACHE = path.join(__dirname, 'mod_modules.json');
const API = 'https://mooncakes.io/api/v0/modules';

async function refresh() {
  process.stdout.write('downloading ' + API + ' ... ');
  const res = await fetch(API);
  if (!res.ok) throw new Error('HTTP ' + res.status);
  const text = await res.text();
  const mods = JSON.parse(text);
  fs.writeFileSync(CACHE, JSON.stringify(mods), 'utf8');
  console.log('ok, ' + mods.length + ' modules -> ' + CACHE);
}

function load() {
  if (!fs.existsSync(CACHE)) {
    console.error('本地缓存不存在，请先运行：node check_topic.js --refresh');
    process.exit(2);
  }
  return JSON.parse(fs.readFileSync(CACHE, 'utf8'));
}

function haystack(m) {
  return [m.name, m.description || '', (m.keywords || []).join(' ')].join(' ');
}

(async () => {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    console.log(fs.readFileSync(__filename, 'utf8').split('*/')[0].replace(/^\/\*\*?/, '').replace(/^\s*\* ?/gm, ''));
    process.exit(1);
  }
  if (args.includes('--refresh')) return refresh();

  const mods = load();
  if (args.includes('--all')) {
    console.log('cached modules: ' + mods.length);
    console.log('cache file: ' + CACHE);
    return;
  }

  const terms = args.filter(a => !a.startsWith('--'));
  console.log('缓存模块数：' + mods.length + '（快照时间见缓存文件修改时间）\n');
  for (const t of terms) {
    const re = new RegExp(t, 'i');
    const hits = mods.filter(m => re.test(haystack(m)));
    const flag = hits.length === 0 ? '  <== 疑似空白' : hits.length <= 2 ? '  <== 接近空白' : '';
    console.log('### ' + t + ' -> ' + hits.length + ' 命中' + flag);
    for (const h of hits.slice(0, 10)) {
      console.log('    - ' + h.name + ' :: ' + (h.description || '').slice(0, 140));
    }
    if (hits.length > 10) console.log('    ... 其余 ' + (hits.length - 10) + ' 个省略');
    console.log('');
  }
})();
