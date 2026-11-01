// 内置苹果 CMS XPath 规则爬虫，对应 jar 的 csp_XPathMac（AndroidCatVodSpider/spider/XPathMac.java）。
// 同 XPath.js，规则额外字段：
//   dcPlayUrl: true  播放页解析 var player_xxx={...}，按 encrypt(1=URL 编码, 2=base64+URL 编码) 解出直链
//   dcVipFlag: true  线路名换成官源 flag；直链是官方站(iqiyi/qq/youku…)时返回 parse:1 jx:1 走解析
//   dcShow2Vip: {"站点线路名": "flag"} 手工映射；pCfgJs: playerconfig.js 地址，从 MacPlayerConfig.player_list 取 show->flag；pCfgJsR: 取值正则
// 直链不是视频格式时回落 parse:1 嗅探播放页。
// App 内没有 XPath 引擎，这里在 cheerio 节点上实现一个小子集，不支持的写法直接抛错：
//   路径：/a  //a  ./a  .//a  ..  .  *  /@attr  /@*  /text()  //text()，多条路径用 | 合并
//   谓词：[n] [last()] [last()-n] [position()<n] [@a] [@a='x'] [@a!='x'] [text()='x']
//         [contains(@a,'x')] [starts-with(@a,'x')] [ends-with(…)] [contains(text(),'x')] [contains(.,'x')]
//         [normalize-space()='x']，可用 and / or / not(…) / 括号组合，多个谓词可连写
//   不支持：显式轴（following-sibling:: 等）、路径结果上的函数（string()/concat()/substring-after() 等）
// 与 JsoupXpath 一致：以 / 开头的表达式相对当前节点求值。
// 本文件是 XPath.js 的拷贝，只改头注释和下面两个开关
// （App 加载器下爬虫间相互 import 不保证可用，冒烟脚本也是单文件加载）。
import { load, Crypto } from 'assets://js/lib/cat.js';

const FILTER = false; // XPathFilter：cateUrl 可带 {area} 等筛选占位符
const MAC = true;    // XPathMac：dcPlayUrl 解 player_xxx 直链，dcVipFlag/dcShow2Vip/pCfgJs 映射官源 flag

const CHROME = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36';
const VIDEO_RE = /http((?!http).){12,}?\.(m3u8|mp4|mkv|flv|mp3|m4a|aac)\?.*|http((?!http).){12,}\.(m3u8|mp4|mkv|flv|mp3|m4a|aac)|http((?!http).)*?video\/tos*/;
const PCFG_RE = '[\\W|\\S|.]*?MacPlayerConfig.player_list[\\W|\\S|.]*?=([\\W|\\S|.]*?),MacPlayerConfig.downer_list';
const VIP_HOSTS = ['iqiyi.com', 'v.qq.com', 'youku.com', 'le.com', 'tudou.com', 'mgtv.com', 'sohu.com', 'acfun.cn',
    'bilibili.com', 'baofeng.com', 'pptv.com'];

// ---------- XPath 子集 ----------
const isEl = n => n && (n.type === 'tag' || n.type === 'script' || n.type === 'style');
const kids = n => (n.children || []).filter(isEl);
const all = (n, out = []) => { for (const c of n.children || []) { out.push(c); all(c, out); } return out; };
const textOf = n => n.type === 'text' ? n.data : (isEl(n) || n.type === 'root') ? (n.children || []).map(textOf).join('') : '';
const fail = (expr, part) => { throw new Error('XPath 不支持：' + expr + (part && part !== expr ? '（' + part + '）' : '')); };
const truthy = v => v !== null && v !== undefined && v !== false;

const FNS = {
    contains: (a, b) => a != null && String(a).includes(b),
    'starts-with': (a, b) => a != null && String(a).startsWith(b),
    'ends-with': (a, b) => a != null && String(a).endsWith(b),
    'normalize-space': a => a == null ? '' : String(a).replace(/\s+/g, ' ').trim(),
};

function compare(a, op, b) {
    if (a == null || b == null) return false;
    if (typeof a === 'number' || typeof b === 'number' || !'=!='.includes(op)) { a = +a; b = +b; }
    else { a = String(a); b = String(b); }
    return op === '=' ? a === b : op === '!=' ? a !== b : op === '<' ? a < b : op === '>' ? a > b : op === '<=' ? a <= b : a >= b;
}

// 在引号、括号外按 sep 切分（sep 可为多字符，如 ' and '）
function cut(s, sep) {
    const out = [];
    let depth = 0, q = '', start = 0;
    for (let i = 0; i < s.length; i++) {
        const c = s[i];
        if (q) { if (c === q) q = ''; continue; }
        if (!depth && s.startsWith(sep, i)) { out.push(s.slice(start, i)); i += sep.length - 1; start = i + 1; }
        else if (c === '"' || c === "'") q = c;
        else if (c === '[' || c === '(') depth++;
        else if (c === ']' || c === ')') depth--;
    }
    out.push(s.slice(start));
    return out;
}

// 最外层括号是否包住整个表达式
function wrapped(s) {
    if (s[0] !== '(' || s[s.length - 1] !== ')') return false;
    let depth = 0, q = '';
    for (let i = 0; i < s.length - 1; i++) {
        const c = s[i];
        if (q) { if (c === q) q = ''; continue; }
        if (c === '"' || c === "'") q = c;
        else if (c === '(') depth++;
        else if (c === ')' && --depth === 0) return false;
    }
    return true;
}

// 谓词内的取值：字符串/数字/@attr/text()/./函数/相对路径
function value(e, node, pos, size, full) {
    e = e.trim();
    let m;
    if ((m = e.match(/^'([^']*)'$|^"([^"]*)"$/))) return m[1] ?? m[2];
    if (/^-?\d+(\.\d+)?$/.test(e)) return +e;
    if ((m = e.match(/^(last|position)\(\)\s*(?:([-+])\s*(\d+))?$/))) {
        const v = m[1] === 'last' ? size : pos;
        return m[2] ? (m[2] === '-' ? v - m[3] : v + +m[3]) : v;
    }
    if ((m = e.match(/^@([\w:-]+)$/))) return (node.attribs || {})[m[1]];
    if (e === 'text()') return (node.children || []).filter(c => c.type === 'text').map(c => c.data).join('');
    if (e === '.' || e === 'string()') return textOf(node);
    if ((m = e.match(/^([\w-]+)\((.*)\)$/s)) && FNS[m[1]]) {
        const args = m[2].trim() ? cut(m[2], ',').map(a => value(a, node, pos, size, full)) : [textOf(node)];
        return FNS[m[1]](...args);
    }
    if (/^\.?\.?\/{0,2}[\w*@-]/.test(e) && !/\(/.test(e.replace(/text\(\)/g, ''))) { // 相对路径：取首个结果的文本
        const r = select(node, e);
        return r.length ? (typeof r[0] === 'string' ? r[0] : textOf(r[0])) : null;
    }
    return fail(full, e);
}

function test(e, node, pos, size, full) {
    e = e.trim();
    if (wrapped(e)) return test(e.slice(1, -1), node, pos, size, full);
    let parts = cut(e, ' or ');
    if (parts.length > 1) return parts.some(p => test(p, node, pos, size, full));
    parts = cut(e, ' and ');
    if (parts.length > 1) return parts.every(p => test(p, node, pos, size, full));
    const m = e.match(/^not\((.*)\)$/s);
    if (m) return !test(m[1], node, pos, size, full);
    for (const op of ['!=', '<=', '>=', '=', '<', '>']) {
        const sides = cut(e, op);
        if (sides.length === 2) return compare(value(sides[0], node, pos, size, full), op, value(sides[1], node, pos, size, full));
    }
    const v = value(e, node, pos, size, full);
    return typeof v === 'number' ? v === pos : truthy(v) && v !== '';
}

// 一步：name[pred][pred]… 作用于同一父节点下的候选列表
function step(list, s, full) {
    const m = s.match(/^(\*|[\w-]+(?::[\w-]+)?)((?:\[.*\])*)$/s);
    if (!m) fail(full, s);
    const name = m[1].toLowerCase();
    let out = list.filter(n => isEl(n) && (name === '*' || n.name === name));
    for (const p of m[2] ? cut(m[2].slice(1, -1), '][') : []) {
        const size = out.length;
        out = out.filter((n, i) => test(p, n, i + 1, size, full));
    }
    return out;
}

// 返回节点或字符串数组；以 / 开头时相对 node 求值
function select(node, expr) {
    expr = (expr || '').trim();
    if (!expr) return [];
    const branches = cut(expr, '|');
    if (branches.length > 1) return [...new Set(branches.flatMap(b => select(node, b)))];
    let e = expr.startsWith('./') ? expr.slice(1) : expr;
    if (e === '.') return [node];
    if (e.includes('::')) fail(expr, e);
    let ctx = [node];
    for (let i = 0; i < e.length;) {
        let axis = 'child';
        if (e.startsWith('//', i)) { axis = 'desc'; i += 2; } else if (e[i] === '/') i++;
        let j = i, depth = 0, q = '';
        for (; j < e.length; j++) {
            const c = e[j];
            if (q) { if (c === q) q = ''; continue; }
            if (c === '"' || c === "'") q = c;
            else if (c === '[' || c === '(') depth++;
            else if (c === ']' || c === ')') depth--;
            else if (!depth && c === '/') break;
        }
        const s = e.slice(i, j).trim();
        i = j;
        if (!s) fail(expr, e);
        const nodes = ctx.filter(n => typeof n !== 'string');
        const scope = axis === 'desc' ? nodes.flatMap(n => [n, ...all(n)]) : nodes;
        let next;
        if (s[0] === '@') {
            const a = s.slice(1);
            if (!/^(\*|[\w:-]+)$/.test(a)) fail(expr, s);
            next = scope.filter(isEl).flatMap(n => a === '*' ? Object.values(n.attribs || {}) : (n.attribs || {})[a] !== undefined ? [n.attribs[a]] : []);
        } else if (s === 'text()') {
            next = scope.flatMap(n => (n.children || []).filter(c => c.type === 'text').map(c => c.data));
        } else if (s === '.') next = scope;
        else if (s === '..') next = scope.map(n => n.parent).filter(Boolean);
        else next = scope.flatMap(n => step(n.children || [], s, expr));
        ctx = [...new Set(next)];
    }
    return ctx;
}

// ---------- 规则 ----------
let ext = '', rule = null, show2Vip = {};

function fetchText(url) { return req(url, { headers: { 'User-Agent': r('ua') || CHROME }, timeout: 15000 }).content || ''; }

function getRule() {
    if (rule) return rule;
    const raw = ext.startsWith('http') ? req(ext, { timeout: 15000 }).content || '' : ext;
    rule = raw.trim() ? JSON.parse(raw) : {};
    if (MAC) for (const [k, v] of Object.entries(rule.dcShow2Vip || {})) show2Vip[k.trim()] = String(v).trim();
    return rule;
}

function r(key) {
    const v = getRule()[key];
    return typeof v === 'string' ? v.trim() : (v || '');
}

// 对应 Rule.doReplaceRegex：匹配到取 group(1)，否则原样
function rx(key, src) {
    const pat = r(key);
    if (!pat) return src;
    try { const m = src.match(new RegExp(pat)); return m && m[1] !== undefined ? m[1].trim() : src; } catch (e) { return src; }
}

function fixUrl(base, src) {
    if (!src) return src;
    if (src.startsWith('//')) return base.split(':')[0] + ':' + src;
    if (!src.includes('://')) return (base.match(/^\w+:\/\/[^/]+/) || [''])[0] + src;
    return src;
}

function isVideo(url) {
    if (['url=http', '.js', '.css', '.html'].some(s => url.includes(s))) return false;
    return VIDEO_RE.test(url);
}

const doc = url => load(fetchText(url)).root()[0];

function one(node, expr) {
    const res = select(node, expr)[0];
    return res === undefined ? '' : (typeof res === 'string' ? res : textOf(res)).trim();
}

function vods(nodes, base, p) {
    return nodes.filter(n => typeof n !== 'string').map(n => ({
        vod_id: rx(p + 'IdR', one(n, r(p + 'Id'))),
        vod_name: rx(p + 'NameR', one(n, r(p + 'Name'))),
        vod_pic: fixUrl(base, rx(p + 'ImgR', one(n, r(p + 'Img')))),
        vod_remarks: r(p + 'Mark') ? rx(p + 'MarkR', one(n, r(p + 'Mark'))) : '',
    }));
}

function cateUrl(tid, pg, filter, extend) {
    let u = r('cateUrl');
    if (!FILTER) return u.replace('{cateId}', tid).replace('{catePg}', String(pg));
    if (filter && extend) for (const [k, v] of Object.entries(extend)) if (v) u = u.split('{' + k + '}').join(encodeURIComponent(String(v)));
    u = u.split('{cateId}').join(tid).split('{catePg}').join(String(pg));
    for (const [, n] of [...u.matchAll(/\{(.*?)\}/g)]) u = u.split('{' + n + '}').join('').split('/' + n + '/').join('');
    return u;
}

function playHeaders() {
    const h = {};
    if (r('playUa')) h['User-Agent'] = r('playUa');
    if (r('playReferer')) h['Referer'] = r('playReferer');
    return h;
}

const unquote = s => s.replace(/(%[0-9A-Fa-f]{2})+/g, m => { try { return decodeURIComponent(m); } catch (e) { return m; } });

// 从播放页脚本解出 player_xxx.url，失败返回 ''
function decodePlayer(html) {
    const m = html.match(/var player_\w+\s*=\s*(\{.*?\})\s*(?:;|<\/script>)/s);
    if (!m) return '';
    try {
        const p = JSON.parse(m[1]);
        let url = p.url || '';
        const enc = String(p.encrypt ?? '0');
        if (enc === '1') url = unquote(url);
        else if (enc === '2') url = unquote(Crypto.enc.Base64.parse(url).toString(Crypto.enc.Utf8));
        return url;
    } catch (e) { return ''; }
}

export default {
    init(e) { ext = typeof e === 'string' ? e.trim() : (e ? JSON.stringify(e) : ''); rule = null; show2Vip = {}; },

    home(filter) {
        const R = getRule(), url = r('homeUrl'), d = doc(url);
        const manual = R.cateManual || {};
        const classes = Object.keys(manual).length
            ? Object.entries(manual).map(([k, v]) => ({ type_id: String(v).trim(), type_name: k.trim() }))
            : select(d, r('cateNode')).map(n => ({ type_id: rx('cateIdR', one(n, r('cateId'))), type_name: rx('cateNameR', one(n, r('cateName'))) }));
        const res = { class: classes, list: r('homeVodNode') ? vods(select(d, r('homeVodNode')), url, 'homeVod') : [] };
        if (R.filter) res.filters = R.filter;
        if (MAC && r('pCfgJs')) { // playerconfig.js 里的 线路展示名 -> flag
            try {
                const m = fetchText(r('pCfgJs')).match(new RegExp(r('pCfgJsR') || PCFG_RE));
                for (const [k, o] of Object.entries(JSON.parse(m[1]))) if (o && o.show && o.show.trim()) show2Vip[o.show.trim()] = k;
            } catch (e) { console.log('playerconfig 解析失败: ' + e); }
        }
        return JSON.stringify(res);
    },

    homeVod() { return JSON.stringify({ list: [] }); },

    category(tid, pg, filter, extend) {
        const url = cateUrl(tid, pg, filter, extend || {});
        return JSON.stringify({ list: vods(select(doc(url), r('cateVodNode')), url, 'cateVod'), page: parseInt(pg) });
    },

    detail(id) {
        const url = r('dtUrl').replace('{vid}', id), d = doc(url);
        const node = select(d, r('dtNode')).find(n => typeof n !== 'string') || d;
        const field = k => r('dt' + k) ? rx('dt' + k + 'R', one(node, r('dt' + k))) : '';
        const froms = select(d, r('dtFromNode')).map(n => rx('dtFromNameR', one(n, r('dtFromName'))));
        const lists = select(d, r('dtUrlNode')).map((n, i) => {
            const eps = select(n, r('dtUrlSubNode')).map(e => rx('dtUrlNameR', one(e, r('dtUrlName'))) + '$' + rx('dtUrlIdR', one(e, r('dtUrlId'))));
            if (!eps.length && i < froms.length) froms[i] = ''; // 排除播放列表为空的播放源
            return eps.join('#');
        });
        let from = froms.filter(Boolean);
        const urls = lists.filter(Boolean).slice(0, from.length);
        if (MAC && getRule().dcVipFlag) from = from.map(f => show2Vip[f] || f);
        return JSON.stringify({
            list: [{
                vod_id: id, vod_name: field('Name'), vod_pic: fixUrl(url, field('Img')), type_name: field('Cate'),
                vod_year: field('Year'), vod_area: field('Area'), vod_remarks: field('Mark'), vod_actor: field('Actor'),
                vod_director: field('Director'), vod_content: field('Desc'),
                vod_play_from: from.join('$$$'), vod_play_url: urls.join('$$$'),
            }],
        });
    },

    search(key, quick, pg) {
        if (!r('searchUrl')) return JSON.stringify({ list: [] });
        const url = r('searchUrl').replace('{wd}', encodeURIComponent(key)), text = fetchText(url), node = r('scVodNode');
        let list;
        if (node.startsWith('json:')) {
            let data = JSON.parse(text);
            for (const k of node.slice(5).split('>')) data = data[k];
            const g = (v, k) => rx(k + 'R', String(v[r(k)] ?? '').trim());
            list = data.map(v => ({ vod_id: g(v, 'scVodId'), vod_name: g(v, 'scVodName'), vod_pic: fixUrl(url, g(v, 'scVodImg')), vod_remarks: g(v, 'scVodMark') }));
        } else list = vods(select(load(text).root()[0], node), url, 'scVod');
        return JSON.stringify({ list, page: parseInt(pg || 1) });
    },

    play(flag, id, flags) {
        const play = r('playUrl'), url = play ? play.replace('{playUrl}', id) : id, R = getRule();
        if (MAC && R.dcPlayUrl) {
            let video = '';
            try { video = decodePlayer(fetchText(url)); } catch (e) { console.log('直链解析失败: ' + e); }
            if (video) {
                if (R.dcVipFlag && VIP_HOSTS.some(h => video.includes(h))) return JSON.stringify({ parse: 1, jx: 1, url: video, header: {} });
                if (R.dcVipFlag && (flags || []).includes(flag)) return JSON.stringify({ parse: 1, url: video, header: {} });
                if (isVideo(video)) return JSON.stringify({ parse: 0, url: video, header: playHeaders() });
            }
        }
        return JSON.stringify({ parse: 1, url, header: playHeaders() });
    },
};
