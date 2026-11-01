// 内置 WebDAV 通用浏览，对应 jar 的 csp_WebDAV（AndroidCatVodSpider/spider/WebDAV.java，含 bean/webdav/*）。
// ext：JSON 或返回该 JSON 的 URL，形如 {"drives": [{"name", "server": "https://host/dav", "user", "pass"}]}；server 的 path 视为挂载根。
// 与 Java 的差异：Java 播放走本地代理转发带鉴权的流；这里直接返回文件 URL + Basic 鉴权 header，
// 字幕 URL 把账号写进 userinfo（字幕无法带 header）。列目录依赖 req 支持 method: 'PROPFIND'。
import { load, Crypto } from 'assets://js/lib/cat.js';

const FOLDER = 'https://x.imgs.ovh/x/2023/09/05/64f680bb030b4.png';
const VIDEO = FOLDER;
const MEDIA = ['mp4', 'mkv', 'wmv', 'flv', 'avi', 'iso', 'mpg', 'ts', 'mp3', 'aac', 'flac', 'm4a', 'ape', 'ogg'];
const SUB = ['srt', 'ass', 'ssa', 'vtt'];
const SUB_FMT = { vtt: 'text/vtt', ass: 'text/x-ssa', ssa: 'text/x-ssa' };
const ALL_EXT = ['ass', 'ssa', 'srt'].concat(MEDIA);
const FILTERS = [
    { key: 'type', name: '排序類型', value: [{ n: '預設', v: '' }, { n: '名稱', v: 'name' }, { n: '大小', v: 'size' }, { n: '修改時間', v: 'date' }] },
    { key: 'order', name: '排序方式', value: [{ n: '預設', v: '' }, { n: '⬆', v: 'asc' }, { n: '⬇', v: 'desc' }] },
];
const PROPFIND = '<?xml version="1.0" encoding="utf-8"?><D:propfind xmlns:D="DAV:"><D:prop>'
    + '<D:resourcetype/><D:getcontentlength/><D:getlastmodified/><D:displayname/></D:prop></D:propfind>';

let ext = '', drives = [];

const getExt = n => n.includes('.') ? n.slice(n.lastIndexOf('.') + 1) : n;
const removeExt = n => n.includes('.') ? n.slice(0, n.lastIndexOf('.')) : n;
const splitId = id => { const i = id.indexOf('/'); return i < 0 ? [id, ''] : [id.slice(0, i), id.slice(i)]; };
const urlPath = u => (u.match(/^\w+:\/\/[^/]+(\/[^?#]*)?/) || [])[1] || '';
// 按段编码路径，保留 '/'
const quote = p => p.split('/').map(encodeURIComponent).join('/');
const dec = s => { try { return decodeURIComponent(s); } catch (e) { return s; } };

function getSize(size) {
    size = Number(size) || 0;
    if (size <= 0) return '';
    for (const [u, n] of [['TB', 1024 ** 4], ['GB', 1024 ** 3], ['MB', 1024 ** 2]]) if (size > n) return (size / n).toFixed(2) + u;
    return (size / 1024).toFixed(2) + 'KB';
}

// PROPFIND 207 -> [{path, name, dir, size, modified}]，path 为解码后的服务器绝对路径。
// 命名空间前缀因服务器而异（D:/d:/无），解析前统一去掉
function parsePropfind(xml) {
    const $ = load(String(xml || '').replace(/<(\/?)[\w.-]+:/g, '<$1'), { xmlMode: true });
    const out = [];
    $('response').each((_, r) => {
        const prop = $(r).find('propstat > prop').first();
        if (!prop.length) return;
        const href = dec($(r).children('href').text().trim().replace(/^\w+:\/\/[^/]+/, '').replace(/[?#].*$/, ''));
        const name = prop.children('displayname').text().trim() || href.replace(/\/+$/, '').split('/').pop();
        const ts = Date.parse(prop.children('getlastmodified').text().trim());
        out.push({
            path: href, name, dir: prop.find('resourcetype > collection').length > 0,
            size: parseInt(prop.children('getcontentlength').text()) || 0, modified: isNaN(ts) ? 0 : ts / 1000,
        });
    });
    return out;
}

function sortItems(type, order, items) {
    if (!['name', 'size', 'date'].includes(type)) return;
    const k = type === 'date' ? 'modified' : type, s = order === 'asc' ? 1 : -1;
    items.sort((a, b) => (a[k] > b[k] ? 1 : a[k] < b[k] ? -1 : 0) * s);
}

function fetchRule() {
    if (drives.length || !ext) return;
    const cfg = JSON.parse((ext.startsWith('http') ? req(ext, { timeout: 15000 }).content : ext) || '{}');
    drives = (cfg.drives || []).filter(d => d.name);
    for (const d of drives) {
        const server = (d.server || '').replace(/\/+$/, '');
        d.path = urlPath(server).replace(/\/+$/, '');
        d.host = d.path ? server.replace(d.path, '') : server;
    }
}

function drive(name) {
    const d = drives.find(d => d.name === name);
    if (!d) throw new Error('WebDAV：未知盘 ' + name);
    return d;
}

function auth(d) {
    return { Authorization: 'Basic ' + Crypto.enc.Base64.stringify(Crypto.enc.Utf8.parse(`${d.user || ''}:${d.pass || ''}`)) };
}

function list(d, path, exts) {
    path = path.startsWith(d.path) ? path : d.path + path;
    if (!path.endsWith('/')) path += '/';
    const rsp = req(d.host + quote(path), {
        method: 'PROPFIND', body: PROPFIND, timeout: 15000,
        headers: Object.assign(auth(d), { Depth: '1', 'Content-Type': 'application/xml' }),
    });
    // 第一条是目录自身
    return parsePropfind(rsp.content).slice(1).filter(i => i.dir || (i.name.includes('.') && exts.includes(getExt(i.name))));
}

const toVod = (d, i, pic) => ({
    vod_id: d.name + i.path, vod_name: i.name, vod_pic: pic,
    vod_remarks: getSize(i.size), vod_tag: i.dir ? 'folder' : 'file',
});

// 同名字幕优先，否则挂上目录内全部字幕
function subsStr(d, res, subs) {
    const tag = i => `~~~${i.name}@@@${getExt(i.name)}@@@${d.name}${i.path}`;
    return subs.filter(i => removeExt(i.name) === removeExt(res.name)).map(tag).join('') || subs.map(tag).join('');
}

function fileUrl(id, withCred) {
    const [key, path] = splitId(id);
    const d = drive(key);
    let host = d.host;
    if (withCred && (d.user || d.pass)) host = host.replace(/^(\w+:\/\/)/, `$1${encodeURIComponent(d.user || '')}:${encodeURIComponent(d.pass || '')}@`);
    return [d, host + quote(path)];
}

export default {
    init(e) {
        ext = typeof e === 'string' ? e.trim() : (e ? JSON.stringify(e) : '');
        drives = [];
        try { fetchRule(); } catch (err) { console.log('WebDAV ext 解析失败: ' + err.message); }
    },

    home(filter) {
        fetchRule();
        const cls = drives.map(d => ({ type_id: d.name, type_name: d.name, type_flag: '1' }));
        return JSON.stringify({ class: cls, filters: Object.fromEntries(cls.map(c => [c.type_id, FILTERS])) });
    },

    homeVod() { return JSON.stringify({ list: [] }); },

    category(tid, pg, filter, extend) {
        fetchRule();
        extend = extend || {};
        // PROPFIND 一次返回整个目录
        if (String(pg) !== '1') return JSON.stringify({ list: [], page: Number(pg), pagecount: 1 });
        const [key, path] = splitId(tid);
        const d = drive(key);
        const items = list(d, path, MEDIA);
        const folders = items.filter(i => i.dir), files = items.filter(i => !i.dir);
        if (extend.type && extend.order) { sortItems(extend.type, extend.order, folders); sortItems(extend.type, extend.order, files); }
        const vods = folders.map(i => toVod(d, i, FOLDER)).concat(files.map(i => toVod(d, i, VIDEO)));
        return JSON.stringify({ list: vods, page: 1, pagecount: 1, limit: vods.length, total: vods.length });
    },

    detail(id) {
        fetchRule();
        const key = splitId(id)[0], parent = id.slice(0, id.lastIndexOf('/'));
        const path = splitId(parent)[1] + '/', name = parent.slice(parent.lastIndexOf('/') + 1);
        const d = drive(key);
        const parents = list(d, path, ALL_EXT);
        const subs = parents.filter(i => SUB.includes(getExt(i.name)));
        sortItems('name', 'asc', parents);
        const urls = parents.filter(i => !i.dir && MEDIA.includes(getExt(i.name).toLowerCase()))
            .map(i => `${i.name}$${d.name}${i.path}${subsStr(d, i, subs)}`);
        return JSON.stringify({ list: [{ vod_id: name, vod_name: name, vod_pic: VIDEO, vod_play_from: key, vod_play_url: urls.join('#') }] });
    },

    search(key, quick, pg) { return JSON.stringify({ list: [] }); },

    play(flag, id, flags) {
        fetchRule();
        const ids = id.split('~~~');
        const [d, url] = fileUrl(ids[0]);
        const subs = ids.slice(1).filter(t => t.includes('@@@')).map(t => {
            const [n, e, sid] = t.split('@@@');
            return { name: n, url: fileUrl(sid, true)[1], format: SUB_FMT[e] || 'application/x-subrip' };
        });
        const res = { parse: 0, url, header: auth(d) };
        if (subs.length) res.subs = subs;
        return JSON.stringify(res);
    },
};
