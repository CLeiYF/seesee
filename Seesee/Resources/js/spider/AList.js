// 内置 AList 通用网盘浏览，对应 jar 的 csp_AList（AndroidCatVodSpider/spider/AList.java，含 bean/alist/*）。
// ext：JSON 或返回该 JSON 的 URL，形如 {"vodPic": "...", "drives": [{"name", "server", "version"?, "search"?, "hidden"?,
//   "login"?: {"username", "password"}, "params"?: [{"path", "pass"}]}]}；server 可带子路径，即挂载根。
import { load } from 'assets://js/lib/cat.js';

const CHROME = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
const FOLDER = 'https://x.imgs.ovh/x/2023/09/05/64f680bb030b4.png';
const MEDIA = ['mp4', 'mkv', 'wmv', 'flv', 'avi', 'iso', 'mpg', 'ts', 'mp3', 'aac', 'flac', 'm4a', 'ape', 'ogg'];
const SUB = ['srt', 'ass', 'ssa', 'vtt'];
const SUB_FMT = { vtt: 'text/vtt', ass: 'text/x-ssa', ssa: 'text/x-ssa' };
const FILTERS = [
    { key: 'type', name: '排序類型', value: [{ n: '預設', v: '' }, { n: '名稱', v: 'name' }, { n: '大小', v: 'size' }, { n: '修改時間', v: 'date' }] },
    { key: 'order', name: '排序方式', value: [{ n: '預設', v: '' }, { n: '⬆', v: 'asc' }, { n: '⬇', v: 'desc' }] },
];

let ext = '', drives = [], vodPic = FOLDER;

const getExt = n => n.includes('.') ? n.slice(n.lastIndexOf('.') + 1) : n;
const isTs = n => n.endsWith('.ts') || n.endsWith('.mpg');
// '盘名/a/b' -> ['盘名', '/a/b']
const splitId = id => { const i = id.indexOf('/'); return i < 0 ? [id, ''] : [id.slice(0, i), id.slice(i)]; };
const urlPath = u => (u.match(/^\w+:\/\/[^/]+(\/[^?#]*)?/) || [])[1] || '';

function getSize(size) {
    size = Number(size) || 0;
    if (size <= 0) return '';
    for (const [u, n] of [['TB', 1024 ** 4], ['GB', 1024 ** 3], ['MB', 1024 ** 2]]) if (size > n) return (size / n).toFixed(2) + u;
    return (size / 1024).toFixed(2) + 'KB';
}

// 文件条目，兼容 v2/v3 字段别名
function item(o) {
    o = o || {};
    const u = o.url || o.raw_url || '';
    return {
        name: o.name || '', path: o.path || o.parent || '', type: Number(o.type) || 0, size: Number(o.size) || 0,
        thumb: o.thumb || o.thumbnail || '', modified: o.modified || o.updated_at || '',
        url: u.startsWith('//') ? 'http:' + u : u,
    };
}
const isFolder = i => i.type === 1;
const isMedia = (i, nw) => isTs(i.name) || (nw ? [2, 3] : [3, 4]).includes(i.type);
const ignore = (i, nw) => !isTs(i.name) && (nw ? [0, 4] : [0, 2, 5]).includes(i.type);
const vodId = (i, id) => id + i.path + '/' + i.name;
const toVod = (i, id, remark) => ({
    vod_id: vodId(i, id), vod_name: i.name, vod_pic: !i.thumb && isFolder(i) ? vodPic : i.thumb,
    vod_remarks: remark ?? getSize(i.size), vod_tag: isFolder(i) ? 'folder' : 'file',
});

function sortItems(type, order, items) {
    if (!['name', 'size', 'date'].includes(type)) return;
    const k = type === 'date' ? 'modified' : type, s = order === 'asc' ? 1 : -1;
    items.sort((a, b) => (a[k] > b[k] ? 1 : a[k] < b[k] ? -1 : 0) * s);
}

function fetchRule() {
    if (drives.length || !ext) return;
    let cfg = ext.startsWith('http') ? req(ext, { headers: { 'User-Agent': CHROME }, timeout: 15000 }).content : ext;
    cfg = JSON.parse(cfg || '{}');
    drives = (cfg.drives || []).filter(d => d.name);
    vodPic = cfg.vodPic || FOLDER;
}

function host(d) {
    const server = (d.server || '').replace(/\/+$/, '');
    return d.path ? server.replace(d.path, '') : server;
}

// 首次使用时补 path（挂载根）与 version（缺省探测 /api/public/settings）
function drive(name) {
    const d = drives.find(d => d.name === name);
    if (!d) throw new Error('AList：未知盘 ' + name);
    if (d.path == null) d.path = urlPath(d.server || '').replace(/\/+$/, '');
    if (!d.version) {
        const txt = req(host(d) + '/api/public/settings', { headers: { 'User-Agent': CHROME }, timeout: 10000 }).content || '';
        d.version = txt.includes('v2.') ? 2 : 3;
    }
    return d;
}

const isNew = d => d.version === 3;

function api(d, kind) {
    const nw = isNew(d);
    return host(d) + {
        list: nw ? '/api/fs/list' : '/api/public/path', get: nw ? '/api/fs/get' : '/api/public/path',
        search: nw ? '/api/fs/search' : '/api/public/search', login: '/api/auth/login',
    }[kind];
}

function pass(d, path) {
    const p = (d.params || []).find(p => path.startsWith(p.path || ''));
    return (p && p.pass) || '';
}

function post(d, url, body, retry = true) {
    const headers = { 'User-Agent': CHROME, 'Content-Type': 'application/json' };
    if (d.token) headers.Authorization = d.token;
    const txt = req(url, { method: 'post', headers, body: JSON.stringify(body), timeout: 15000 }).content || '';
    if (retry && txt.includes('Guest user is disabled') && login(d)) return post(d, url, body, false);
    return txt;
}

// 游客被禁用时用 ext 里的账号登录
function login(d) {
    try {
        const l = d.login || {};
        const body = JSON.stringify({ username: l.username || '', password: l.password || '' });
        const rsp = JSON.parse(req(api(d, 'login'), { method: 'post', headers: { 'Content-Type': 'application/json' }, body, timeout: 15000 }).content);
        d.token = rsp.data.token;
        return !!d.token;
    } catch (e) { return false; }
}

function fullPath(id) {
    const [key, path] = splitId(id);
    const d = drive(key), root = d.path || '';
    return [d, (path.startsWith(root) ? path : root + path) || '/'];
}

function list(id, filter) {
    try {
        const [d, path] = fullPath(id);
        const data = JSON.parse(post(d, api(d, 'list'), { path, password: pass(d, path) })).data;
        const items = ((isNew(d) ? data.content : data.files) || []).map(item);
        return items.filter(i => !(filter && ignore(i, isNew(d))));
    } catch (e) { return []; }
}

function getItem(id) {
    try {
        const [d, path] = fullPath(id);
        const data = JSON.parse(post(d, api(d, 'get'), { path, password: pass(d, path) })).data;
        return item(isNew(d) ? data : data.files[0]);
    } catch (e) { return item(); }
}

function searchAList(d, key) {
    try {
        const nw = isNew(d);
        const body = nw ? { keywords: key, page: 1, parent: '/', per_page: 100 } : { keyword: key, path: '/' };
        const data = JSON.parse(post(d, api(d, 'search'), body)).data;
        return ((nw ? data.content : data) || []).map(item).filter(i => !ignore(i, nw)).map(i => toVod(i, d.name, d.name));
    } catch (e) { return []; }
}

// 小雅 AList 的 /search 页面：每个 <a> 文本为 "路径#...#封面"
function searchXiaoya(d, key) {
    let $;
    try {
        $ = load(req(host(d) + '/search?box=' + encodeURIComponent(key) + '&url=&type=video', { headers: { 'User-Agent': CHROME }, timeout: 15000 }).content || '');
    } catch (e) { return []; }
    const out = [];
    $('ul > a').each((_, a) => {
        const sp = $(a).text().split('#');
        if (!sp[0].includes('/')) return;
        const idx = sp[0].lastIndexOf('/');
        const it = item({ name: sp[0].slice(idx + 1), path: '/' + sp[0].slice(0, idx), type: MEDIA.includes(getExt(sp[0]).toLowerCase()) ? 0 : 1, thumb: sp[4] || '' });
        out.push(toVod(it, d.name, d.name));
    });
    return out;
}

function playHeader(url) {
    const h = url.split('/')[2] || '';
    if (h.includes('115.com')) return { 'User-Agent': CHROME };
    if (h.includes('baidupcs.com')) return { 'User-Agent': 'pan.baidu.com' };
    return {};
}

export default {
    init(e) {
        ext = typeof e === 'string' ? e.trim() : (e ? JSON.stringify(e) : '');
        drives = [];
        try { fetchRule(); } catch (err) { console.log('AList ext 解析失败: ' + err.message); }
    },

    home(filter) {
        fetchRule();
        const cls = drives.filter(d => !d.hidden).map(d => ({ type_id: d.name, type_name: d.name, type_flag: '1' }));
        return JSON.stringify({ class: cls, filters: Object.fromEntries(cls.map(c => [c.type_id, FILTERS])) });
    },

    homeVod() { return JSON.stringify({ list: [] }); },

    category(tid, pg, filter, extend) {
        fetchRule();
        extend = extend || {};
        // AList 一次返回整个目录，无分页
        if (String(pg) !== '1') return JSON.stringify({ list: [], page: Number(pg), pagecount: 1 });
        const items = list(tid, true);
        const folders = items.filter(isFolder), files = items.filter(i => !isFolder(i));
        if (extend.type && extend.order) { sortItems(extend.type, extend.order, folders); sortItems(extend.type, extend.order, files); }
        const vods = folders.concat(files).map(i => toVod(i, tid));
        return JSON.stringify({ list: vods, page: 1, pagecount: 1, limit: vods.length, total: vods.length });
    },

    // id 为文件，取同目录所有媒体作选集，字幕拼在每集后面（~~~名@@@扩展名@@@id）
    detail(id) {
        fetchRule();
        const key = splitId(id)[0], path = id.slice(0, id.lastIndexOf('/'));
        const d = drive(key);
        const parents = list(path, false);
        sortItems('name', 'asc', parents);
        const subs = parents.filter(i => SUB.includes(getExt(i.name))).map(i => `~~~${i.name}@@@${getExt(i.name)}@@@${vodId(i, path)}`).join('');
        const urls = parents.filter(i => isMedia(i, isNew(d))).map(i => `${i.name}$${vodId(i, path)}${subs}`);
        return JSON.stringify({ list: [{
            vod_id: id, vod_name: path.slice(path.lastIndexOf('/') + 1), vod_pic: vodPic,
            vod_play_from: key, vod_play_url: urls.join('#'),
        }] });
    },

    search(key, quick, pg) {
        fetchRule();
        if (pg && String(pg) !== '1') return JSON.stringify({ list: [], page: Number(pg) });
        const out = [];
        for (const d0 of drives.filter(d => d.search !== false)) {
            let d;
            try { d = drive(d0.name); } catch (e) { continue; }
            const r = searchAList(d, key);
            out.push(...(r.length ? r : searchXiaoya(d, key)));
        }
        return JSON.stringify({ list: out, page: 1 });
    },

    play(flag, id, flags) {
        fetchRule();
        const ids = id.split('~~~');
        const url = getItem(ids[0]).url;
        const subs = ids.slice(1).filter(t => t.includes('@@@')).map(t => {
            const [name, e, sid] = t.split('@@@');
            return { name, url: getItem(sid).url, format: SUB_FMT[e] || 'application/x-subrip' };
        });
        const res = { parse: 0, url, header: playHeader(url) };
        if (subs.length) res.subs = subs;
        return JSON.stringify(res);
    },
};
