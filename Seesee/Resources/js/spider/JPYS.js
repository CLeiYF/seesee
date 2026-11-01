// 内置金牌影视，对应 itv 配置里的 ./python/JPYS.py（金牌PY）。
// 去掉了原 py 的 LogReportManager 日志上报（开发调试用）。
import { Crypto } from 'assets://js/lib/cat.js';

const KEY = 'cb808529bae6b6be45ecfab29a4889bc';
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; ) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.6478.61 Chrome/126.0.6478.61 Not/A)Brand/8  Safari/537.36';
let host = '';

const qs = p => Object.entries(p).map(([k, v]) => k + '=' + v).join('&');

function uuid() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
        const r = Math.random() * 16 | 0;
        return (c === 'x' ? r : (r & 3 | 8)).toString(16);
    });
}

// 签名：参数（按传入顺序）+ key + t 拼成 a=b&c=d，先 md5 再 sha1
function headers(param = {}) {
    const t = String(Date.now());
    const sign = Crypto.SHA1(Crypto.MD5(qs({ ...param, key: KEY, t })).toString()).toString();
    return { 'User-Agent': UA, Accept: 'application/json, text/plain, */*', sign, t, deviceid: uuid() };
}

function api(path, param) {
    // 签名用原文，URL 里再编码（同 py：签名拼原值，requests 发请求时编码）
    const enc = param && Object.fromEntries(Object.entries(param).map(([k, v]) => [k, encodeURIComponent(v)]));
    const url = host + '/api/mw-movie/anonymous' + path + (enc ? '?' + qs(enc) : '');
    return JSON.parse(req(url, { headers: headers(param), timeout: 15000 }).content || '{}');
}

// 字段名转成 vod_xxx / type_xxx（vodName → vod_name）
function vod(item) {
    const out = {};
    for (const [k, v] of Object.entries(item)) {
        let f = k.toLowerCase();
        if (f.startsWith('vod') && f.length > 3) f = f.replace('vod', 'vod_');
        if (f.startsWith('type') && f.length > 4) f = f.replace('type', 'type_');
        out[f] = v;
    }
    return out;
}

// ponytail: 原 py 并发 HEAD 测速取最快；这里按顺序取第一个 2 秒内能连上的，域名多了再并发
function pickHost(list) {
    const urls = list.split(',').map(s => s.trim()).filter(Boolean);
    for (const u of urls) {
        if (req(u, { method: 'head', timeout: 2000, redirect: 0 }).code > 0) return u;
    }
    return urls[0] || '';
}

export default {
    init(ext) {
        const cfg = typeof ext === 'string' ? (ext.trim().startsWith('{') ? JSON.parse(ext) : { site: ext }) : (ext || {});
        host = pickHost(cfg.site || 'https://www.jiabaide.cn').replace(/\/$/, '');
    },

    home(filter) {
        const cdata = api('/get/filer/type'), fdata = api('/v1/get/filer/list');
        const classes = (cdata.data || []).map(k => ({ type_name: k.typeName, type_id: String(k.typeId) }));
        const opts = (list, val = 'itemText') => (list || []).map(i => ({ n: i.itemText, v: i[val] }));
        const filters = {};
        for (const [tid, d] of Object.entries(fdata.data || {})) {
            const sort = [{ n: '最近更新', v: '2' }, { n: '人气高低', v: '3' }, { n: '评分高低', v: '4' }];
            if (tid === '1') sort.shift();
            filters[tid] = [
                { key: 'type', name: '类型', value: opts(d.typeList, 'itemValue') },
                ...(d.plotList && d.plotList.length ? [{ key: 'v_class', name: '剧情', value: opts(d.plotList) }] : []),
                { key: 'area', name: '地区', value: opts(d.districtList) },
                { key: 'year', name: '年份', value: opts(d.yearList) },
                { key: 'lang', name: '语言', value: opts(d.languageList) },
                { key: 'sort', name: '排序', value: sort },
            ];
        }
        return JSON.stringify({ class: classes, filters });
    },

    homeVod() {
        const all = api('/v1/home/all/list'), hot = api('/home/hotSearch');
        const list = [];
        for (const i of Object.values(all.data || {})) list.push(...(i.list || []));
        list.push(...(hot.data || []));
        return JSON.stringify({ list: list.map(vod) });
    },

    category(tid, pg, filter, extend) {
        const e = extend || {};
        const p = {
            area: e.area || '', filterStatus: '1', lang: e.lang || '', pageNum: pg, pageSize: '30',
            sort: e.sort || '1', sortBy: '1', type: e.type || '', type1: tid, v_class: e.v_class || '', year: e.year || '',
        };
        const data = api('/video/list', p);
        return JSON.stringify({ list: ((data.data || {}).list || []).map(vod), page: parseInt(pg), pagecount: 9999, limit: 90, total: 999999 });
    },

    detail(id) {
        const v = vod(api('/video/detail', { id }).data || {});
        const eps = v.episodelist || [];
        v.vod_play_from = '金牌';
        v.vod_play_url = eps.map(i => (eps.length > 1 ? i.name : v.vod_name) + '$' + id + '@@' + i.nid).join('#');
        delete v.episodelist;
        return JSON.stringify({ list: [v] });
    },

    search(key, quick, pg) {
        const data = api('/video/searchByWord', { keyword: key, pageNum: pg || '1', pageSize: '8', sourceCode: '1' });
        return JSON.stringify({ list: (((data.data || {}).result || {}).list || []).map(vod), page: parseInt(pg || 1) });
    },

    play(flag, id, flags) {
        const [vid, nid] = id.split('@@');
        const data = api('/v2/video/episode/url', { clientType: '1', id: vid, nid });
        const url = [];
        for (const i of (data.data || {}).list || []) url.push(i.resolutionName, i.url);
        const header = {
            'User-Agent': UA, 'sec-ch-ua-platform': '"Windows"', DNT: '1',
            'sec-ch-ua': '"Not/A)Brand";v="8", "Chromium";v="126", "Google Chrome";v="126"',
            'sec-ch-ua-mobile': '?0', Origin: host, Referer: host + '/',
        };
        return JSON.stringify({ parse: 0, url, header });
    },
};
