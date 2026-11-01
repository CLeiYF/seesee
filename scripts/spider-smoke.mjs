// 内置 JS 爬虫的联网冒烟检查（不进 App、不进 XCTest）：
//   node scripts/spider-smoke.mjs            跑全部
//   node scripts/spider-smoke.mjs Jianpian   只跑一个
// 每个 spider-smoke/<Name>.mjs 导出 default async (s, assert) => {...}，s 为已 init 的爬虫（返回值已 JSON.parse）。
// req / cat.js 用 Node 模拟 App 内 JSRuntime 的行为：req 同步、返回 {code, headers, content}。
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, readdirSync, mkdtempSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const js = join(root, 'Seesee/Resources/js');
const tmp = mkdtempSync(join(tmpdir(), 'spider-'));

globalThis.req = (url, o = {}) => {
  const args = ['-s', '-L', '-m', String(Math.ceil((o.timeout || 15000) / 1000)), '-D', '-', '-o', join(tmp, 'body')];
  if (process.env.NO_PROXY_ALL) args.push('--noproxy', '*');
  for (const [k, v] of Object.entries(o.headers || {})) args.push('-H', `${k}: ${v}`);
  const method = (o.method || 'get').toUpperCase();
  // POST 总带 body（可为空）；其它非 GET/HEAD 方法（如 PROPFIND）有 body 时才带
  if (method === 'POST' || (!['GET', 'HEAD'].includes(method) && (o.body ?? o.data) != null)) {
    const d = o.body ?? o.data ?? '';
    const isJson = typeof d === 'object' && (o.postType || 'json') === 'json';
    const body = typeof d === 'object' ? (isJson ? JSON.stringify(d) : new URLSearchParams(d).toString()) : String(d);
    args.push('--data-binary', body);
    if (typeof d === 'object') args.push('-H', `Content-Type: ${isJson ? 'application/json' : 'application/x-www-form-urlencoded'}`);
  }
  if (!['GET', 'HEAD'].includes(method)) args.push('-X', method);
  if (o.redirect === 0) args.splice(args.indexOf('-L'), 1);
  args.push(url);
  let head = '';
  try { head = execFileSync('curl', args).toString(); } catch { return { code: 0, headers: {}, content: '' }; }
  const blocks = head.trim().split(/\r?\n\r?\n/);
  const last = blocks[blocks.length - 1].split(/\r?\n/);
  const headers = {};
  // 同名头（如多条 Set-Cookie）像 URLSession 的 allHeaderFields 一样用 ", " 合并
  for (const l of last.slice(1)) {
    const i = l.indexOf(':'); if (i <= 0) continue;
    const k = l.slice(0, i).trim().toLowerCase(), v = l.slice(i + 1).trim();
    headers[k] = k in headers ? headers[k] + ', ' + v : v;
  }
  const buf = readFileSync(join(tmp, 'body'));
  const content = o.buffer === 2 ? buf.toString('base64') : buf.toString('utf8');
  return { code: parseInt(last[0].split(' ')[1]) || 0, headers, content };
};
for (const [k, v] of Object.entries({ md5X: s => require_('crypto').createHash('md5').update(s).digest('hex') })) globalThis[k] = v;
function require_(m) { return globalThis.process.getBuiltinModule(m); }
// local.get/set/delete：内存版（App 内为 UserDefaults）
const store = new Map();
globalThis.joinUrl = (base, ref) => { try { return new URL(ref, base).href; } catch { return ref; } };
globalThis.local = { get: (r, k) => store.get(r + '_' + k) ?? '', set: (r, k, v) => void store.set(r + '_' + k, String(v)), delete: (r, k) => void store.delete(r + '_' + k) };

// 把整个 js 目录复制到临时目录，assets://js/... 改写成临时目录里的文件，
// 这样爬虫里的相对 import（如 './pan/cloud.js'）及其内部的 assets:// 也能解析
const staged = join(tmp, 'js');
(function stage(dir) {
  for (const e of readdirSync(join(js, dir), { withFileTypes: true })) {
    const rel = join(dir, e.name);
    if (e.isDirectory()) { mkdirSync(join(staged, rel), { recursive: true }); stage(rel); continue; }
    if (!e.name.endsWith('.js')) continue;
    const src = readFileSync(join(js, rel), 'utf8')
      .replace(/(['"])assets:\/\/js\/([^'"]+)\1/g, (_, q, p) => q + pathToFileURL(join(staged, p)).href + q);
    writeFileSync(join(staged, rel), src);
  }
})('');
async function load(name) {
  return (await import(pathToFileURL(join(staged, 'spider', name + '.js')).href)).default;
}

const parse = v => (typeof v === 'string' ? JSON.parse(v || '{}') : v);
const only = process.argv[2];
let failed = 0;
for (const file of readdirSync(join(root, 'scripts/spider-smoke')).filter(f => f.endsWith('.mjs')).sort()) {
  const name = file.replace(/\.mjs$/, '');
  if (only && only !== name) continue;
  const check = await import(pathToFileURL(join(root, 'scripts/spider-smoke', file)).href);
  try {
    const raw = await load(check.spider || name);
    await raw.init?.(check.ext ?? '');
    const s = new Proxy(raw, { get: (t, k) => typeof t[k] === 'function' ? async (...a) => parse(await t[k](...a)) : t[k] });
    const msg = await check.default(s, assert);
    console.log('ok  ', name, msg || '');
  } catch (e) {
    failed++;
    console.log('FAIL', name, e.message.split('\n')[0]);
  }
}
process.exit(failed ? 1 : 0);
