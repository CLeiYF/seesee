// App 影视通用接口，对应 jar 的 csp_AppYsV2（AndroidCatVodSpider/spider/AppYsV2.java）。
// ext 为接口地址（"###" 后忽略），按 URL 特征区分三类：
//   1. 苹果CMS app 插件：.../api.php/app/ 或含 xgapp（nav / video / video_detail / search）
//   2. v1.vod 插件：     .../api.php/v1.vod（/types /vodPhbAll /detail?vod_id= ?wd=）
//   3. TV 接口：         .../api.php/xxx/vod（?ac=list&class=）
const CHROME = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36';
const VIDEO_RE = /http((?!http).){12,}?\.(m3u8|mp4|mkv|flv|mp3|m4a|aac)\?.*|http((?!http).){12,}\.(m3u8|mp4|mkv|flv|mp3|m4a|aac)|http((?!http).)*?video\/tos*/;
const VIP_HOSTS = ['iqiyi.com', 'v.qq.com', 'youku.com', 'le.com', 'tudou.com', 'mgtv.com', 'sohu.com', 'acfun.cn', 'bilibili.com', 'baofeng.com', 'pptv.com'];
const TV_PAT = /api\.php\/.*?\/vod/;
const PARSE_PAT1 = /.*(url|v|vid|php\?id)=/;
const PARSE_PAT2 = /https?:\/\/[^/]*/;
const HTML_SNIFF = [/player=new/, /<div id="video"/, /<div id="[^"]*?player"/, /\/\/视频链接/, /HlsJsPlayer\(/, /<iframe[\s\S]*?src="[^"]+?"/, /<video[\s\S]*?src="[^"]+?"/];
const WD_SITES = ['esellauto', '1.14.63.101', 'zjys', 'dcd', 'lxue', 'weetai.cn', 'haokanju1', 'fit:8', 'zjj.life', 'love9989',
    '8d8q', 'lk.pxun', 'hgyx', '521x5', 'lxyyy', '0818tv', 'diyoui', 'diliktv', 'ppzhu', 'aitesucai', 'zz.ci',
    'chxjon', 'watchmi', 'vipbp', 'bhtv', 'xfykl'];
const years = []; for (let y = 2023; y >= 2000; y--) years.push(y);
const TV_FILTERS = '分类+全部=+电影=movie+连续剧=tvplay+综艺=tvshow+动漫=comic+4K=movie_4k+体育=tiyu\n'
    + '筛选class+全部=+喜剧+爱情+恐怖+动作+科幻+剧情+战争+警匪+犯罪+动画+奇幻+武侠+冒险+枪战+恐怖+悬疑+惊悚+经典+青春+文艺+微电影+古装+历史+运动+农村+惊悚+惊悚+伦理+情色+福利+三级+儿童+网络电影\n'
    + '筛选area+全部=+大陆+香港+台湾+美国+英国+法国+日本+韩国+德国+泰国+印度+西班牙+加拿大+其他\n'
    + '筛选year+全部=+' + years.join('+');
const FILTER_NAMES = { class: '类型', area: '地区', lang: '语言', year: '年份' };

let api = '';
let parseMap = {}; // flag -> 解析地址列表（detail 写入，play 使用）

const has = (s, arr) => arr.some(x => s.includes(x));
const isObj = o => o && typeof o === 'object' && !Array.isArray(o);
const str = v => (v == null ? '' : String(v));

function isVideo(url) {
    if (has(url, ['url=http', '.js', '.css', '.html'])) return false;
    return VIDEO_RE.test(url);
}

const isApp = a => a.includes('api.php/app') || a.includes('xgapp');

function ua(a) {
    if (a.includes('vod.9e03.com')) return 'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.0.0 Mobile Safari/537.36';
    if (isApp(a) || a.includes('freekan')) return 'Dart/2.14 (dart:io)';
    if (has(a, ['zsb', 'fkxs', 'xays', 'xcys', 'szys', 'dxys', 'ytys', 'qnys'])) return 'Dart/2.15 (dart:io)';
    return a.includes('.vod') ? 'okhttp/4.1.0' : 'Dalvik/2.1.0';
}

function getJson(url) {
    return JSON.parse(req(url, { headers: { 'User-Agent': ua(url) }, timeout: 15000 }).content || '{}');
}

function pickList(o) {
    if (Array.isArray(o.list)) return o.list;
    if (isObj(o.data) && Array.isArray(o.data.list)) return o.data.list;
    return Array.isArray(o.data) ? o.data : [];
}

function toVod(v) {
    if ('vod_id' in v) return { vod_id: str(v.vod_id), vod_name: str(v.vod_name), vod_pic: str(v.vod_pic), vod_remarks: str(v.vod_remarks) };
    return { vod_id: str(v.nextlink), vod_name: str(v.title), vod_pic: str(v.pic), vod_remarks: str(v.state) };
}

const joinArr = a => (Array.isArray(a) ? a.join(',') : '');

// ---------- URL 规则（与 Java 同名方法一一对应） ----------
function cateUrl() {
    if (isApp(api)) return api + 'nav?token=';
    if (api.includes('.vod')) return api + (api.includes('iopenyun.com') ? '/list?type' : '/types');
    return '';
}

function catePrefix() {
    if (isApp(api)) return (api.includes('dijiaxia') ? 'http://www.dijiaxia.com/api.php/app/' : api) + 'video?tid=';
    if (api.includes('.vod')) {
        if (api.includes('tv.bulei.cc')) return 'https://tv.bulei.cc/api2.php/v1.vod?type=';
        return api + (api.includes('iopenyun') ? '/list?type=' : '?type=');
    }
    return api + '?ac=list&class=';
}

function cateSuffix() {
    if (isApp(api)) return '&class=筛选class&area=筛选area&lang=筛选lang&year=筛选year&limit=18&pg=#PN#';
    if (api.includes('.vod')) return '&class=筛选class&area=筛选area&lang=筛选lang&year=筛选year&by=排序&limit=18&page=#PN#';
    return '&page=#PN#&area=筛选area&type=筛选class&start=筛选year';
}

function filterTypes(ext) {
    let s = '';
    if (typeof ext === 'string') { try { ext = JSON.parse(ext); } catch (e) { ext = null; } }
    for (const [k, v] of Object.entries(isObj(ext) ? ext : {})) {
        if (k in FILTER_NAMES && typeof v === 'string') s += '筛选' + k + '+全部=+' + v.replace(/,/g, '+') + '\n';
    }
    if (api.includes('.vod')) s += '\n排序+全部=+最新=time+最热=hits+评分=score';
    else if (!isApp(api)) s = TV_FILTERS;
    return s;
}

function recommendUrl() {
    if (isApp(api)) return api + 'index_video?token=';
    return api.includes('.vod') ? api + '/vodPhbAll' : '';
}

function detailPrefix() {
    let a = api;
    if (isApp(a)) {
        if (a.includes('dijiaxia')) a = 'https://www.dijiaxia.com/api.php/app/';
        else if (a.includes('1010dy')) a = 'http://www.1010dy.cc/api.php/app/';
        return a + 'video_detail?id=';
    }
    if (a.includes('.vod')) return a + (a.includes('iopenyun') ? '/detailID?vod_id=' : '/detail?vod_id=');
    return '';
}

function searchUrl(key) {
    const a = api;
    if (a.includes('.vod')) return a + (a.includes('iopenyun.com') ? '/list?wd=' : '?wd=') + key + '&page=';
    if (isApp(a)) return a + 'search?text=' + key + '&pg=';
    if (TV_PAT.test(a)) return a + '?ac=list&' + (has(a, WD_SITES) ? 'wd=' : 'zm=') + key + '&page=';
    return '';
}

function addParse(flag, purl) {
    const lst = parseMap[flag] || (parseMap[flag] = []);
    if (purl && !lst.includes(purl)) lst.push(purl);
}

// 解析接口返回 JSON 时提取直链和 header，失败返回 null（对应 Java jsonParse）
function jsonParse(src, text) {
    let o = JSON.parse(text);
    if (!isObj(o)) return null;
    if (isObj(o.data) && !('url' in o)) o = o.data;
    let url = str(o.url || '');
    if (url.startsWith('//')) url = 'https:' + url;
    if (!url.trim().startsWith('http')) return null;
    if (url === src && (has(url, VIP_HOSTS) || !isVideo(url))) return null;
    if (url.includes('973973.xyz') || url.includes('.fit:')) return null;
    let header = {};
    for (const k of ['header', 'Header', 'headers', 'Headers']) if (isObj(o[k])) { header = Object.assign({}, o[k]); break; }
    const u = str(o['user-agent'] || o['User-Agent'] || '');
    if (u.trim()) header['User-Agent'] = u;
    const r = str(o.referer || o.Referer || '');
    if (r.trim()) header['Referer'] = r;
    if (src.includes('www.mgtv.com') || url.includes('titan.mgtv')) Object.assign(header, { Referer: '', 'User-Agent': 'Mozilla/5.0' });
    else if (src.includes('bilibili')) Object.assign(header, { Referer: 'https://www.bilibili.com/', 'User-Agent': CHROME });
    return { parse: 0, url, header };
}

// 递归收集 key 对应的数组
function findArrays(o, key, out) {
    if (Array.isArray(o)) o.forEach(x => findArrays(x, key, out));
    else if (isObj(o)) for (const [k, v] of Object.entries(o)) { if (k === key && Array.isArray(v)) out.push(v); findArrays(v, key, out); }
    return out;
}

export default {
    init(e) { api = str(e).split('###')[0].trim(); parseMap = {}; },

    home(filter) {
        const url = cateUrl();
        let types, start = 0;
        if (url) types = pickList(getJson(url));
        else { // TV 接口：从内置筛选第一行读分类
            types = TV_FILTERS.split('\n')[0].split('+').slice(1).map(kv => kv.trim().split('='))
                .filter(kv => kv.length >= 2 && kv[1].trim()).map(kv => ({ type_name: kv[0].trim(), type_id: kv[1].trim() }));
            start = 1;
        }
        const classes = [], filters = {};
        for (const t of types) {
            const tid = str(t.type_id);
            classes.push({ type_id: tid, type_name: str(t.type_name) });
            if (!filter) continue;
            filters[tid] = filterTypes(t.type_extend).split('\n').slice(start).map(l => l.trim()).filter(Boolean).map(line => {
                const parts = line.split('+');
                const key = parts[0].trim().replace('筛选', '');
                const value = parts.slice(1).map(kv => {
                    kv = kv.trim();
                    const i = kv.indexOf('=');
                    return i >= 0 ? { n: kv.slice(0, i).trim(), v: kv.slice(i + 1).trim() } : { n: kv, v: kv };
                });
                return { key, name: FILTER_NAMES[key] || key, value };
            });
        }
        return JSON.stringify({ class: classes, filters });
    },

    homeVod() {
        const url = recommendUrl();
        if (!url) return JSON.stringify({ list: (getJson(catePrefix() + 'movie&page=1&area=&type=&start=').data || []).map(toVod) });
        const obj = getJson(url);
        let arrays = findArrays(obj, 'vlist', []);
        if (!arrays.length) arrays = findArrays(obj, 'vod_list', []);
        const list = [], seen = new Set();
        for (const v of arrays.flat()) {
            if (isObj(v) && 'vod_id' in v && !seen.has(str(v.vod_id))) { seen.add(str(v.vod_id)); list.push(toVod(v)); }
        }
        return JSON.stringify({ list });
    },

    category(tid, pg, filter, extend) {
        extend = extend || {};
        let url = (catePrefix() + tid + cateSuffix()).replace('#PN#', pg);
        for (const k of ['class', 'area', 'lang', 'year']) url = url.replace('筛选' + k, extend[k] || '');
        url = url.replace('排序', extend['排序'] || '');
        const obj = getJson(url), d = obj.data;
        let pagecount = 9999;
        if (Number.isInteger(obj.totalpage)) pagecount = obj.totalpage;
        else if (Number.isInteger(obj.pagecount)) pagecount = obj.pagecount;
        else if (isObj(d) && Number.isInteger(d.total) && d.limit) pagecount = Math.ceil(d.total / d.limit);
        return JSON.stringify({ list: pickList(obj).map(toVod), page: parseInt(pg), pagecount });
    },

    detail(id) {
        const a = api, obj = getJson(detailPrefix() + id);
        const froms = [], urls = [];
        let vod;
        if (isApp(a) || a.includes('.vod')) {
            const d = (a.includes('xgapp') && !a.includes('api.php/app/') ? obj.data.vod_info : obj.data) || {};
            vod = { vod_id: str(d.vod_id ?? id), vod_name: str(d.vod_name), vod_pic: str(d.vod_pic), type_name: str(d.vod_class),
                vod_year: str(d.vod_year), vod_area: str(d.vod_area), vod_remarks: str(d.vod_remarks), vod_actor: str(d.vod_actor),
                vod_director: str(d.vod_director), vod_content: str(d.vod_content) };
            if (a.includes('.vod') && !isApp(a)) {
                for (const f of d.vod_play_list || []) {
                    const info = f.player_info || {};
                    const flag = str(info.from).trim() || str(info.show).trim();
                    froms.push(flag); urls.push(str(f.url));
                    for (let purl of str(info.parse).split(',').concat(str(info.parse2).split(','))) {
                        if (purl.includes('http')) { const m = purl.match(PARSE_PAT1); if (m) purl = m[0]; }
                        else if (purl.includes('//')) { const m = purl.match(PARSE_PAT1); if (m) purl = 'http:' + m[0]; }
                        else { // 与 Java 一致：用接口地址拼
                            const m = a.match(PARSE_PAT2), m1 = a.match(PARSE_PAT1);
                            if (m && m1) purl = m[0] + m1[0];
                        }
                        addParse(flag, purl.replace(/\.\./g, '.').trim());
                    }
                }
            } else {
                for (const f of d.vod_url_with_player || []) {
                    const flag = str(f.code).trim() || str(f.name).trim();
                    froms.push(flag); urls.push(str(f.url));
                    addParse(flag, str(f.parse_api).trim());
                }
            }
        } else { // TV 接口
            vod = { vod_id: str(obj.vod_id ?? id), vod_name: str(obj.title), vod_pic: str(obj.img_url), type_name: joinArr(obj.type),
                vod_year: str(obj.pubtime), vod_area: joinArr(obj.area), vod_remarks: str(obj.trunk), vod_actor: joinArr(obj.actor),
                vod_director: joinArr(obj.director), vod_content: str(obj.intro) };
            for (const [flag, eps] of Object.entries(obj.videolist || {})) {
                parseMap[flag] = parseMap[flag] || [];
                const lst = eps.map(e => {
                    let u = str(e.url);
                    const i = u.indexOf('url=');
                    if (i >= 0) { addParse(flag, u.slice(0, i + 4).trim()); u = u.slice(i + 4).trim(); }
                    return str(e.title) + '$' + u;
                });
                froms.push(flag); urls.push(lst.join('#'));
            }
        }
        vod.vod_play_from = froms.join('$$$');
        vod.vod_play_url = urls.join('$$$');
        return JSON.stringify({ list: [vod] });
    },

    search(key, quick, pg) {
        pg = pg || 1;
        const url = searchUrl(encodeURIComponent(key));
        if (!url) return JSON.stringify({ list: [] });
        return JSON.stringify({ list: pickList(getJson(url + pg)).map(toVod), page: parseInt(pg) });
    },

    play(flag, id, flags) {
        if (flag.includes('fanqie') && isVideo(id)) return JSON.stringify({ parse: 0, url: id, header: {} });
        let htmlParse = '';
        for (const purl of parseMap[flag] || []) {
            if (!purl || purl === 'null') continue;
            const text = req(purl + id, { timeout: 10000 }).content || '';
            if (!text) continue;
            try { const r = jsonParse(id, text); if (r) return JSON.stringify(r); } catch (e) { /* 非 JSON */ }
            if (text.includes('<html') && HTML_SNIFF.some(p => p.test(text))) htmlParse = purl;
        }
        // 网页解析：交给壳子嗅探 playUrl+url
        if (htmlParse) return JSON.stringify({ parse: 1, playUrl: htmlParse, url: id, header: {} });
        if (isVideo(id)) return JSON.stringify({ parse: 0, url: id, header: {} });
        return JSON.stringify({ parse: 1, jx: 1, url: id, header: {} });
    },
};
