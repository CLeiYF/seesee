// 内置哔哩（音乐/少儿/课堂），对应 itv 单线路包 custom_spider_modified.jar 的 csp_Bili。
// 分类即搜索关键词：category(tid) = 搜索 "tid [extend.tid]"，按 order/duration 筛选。
// ponytail: 跳过 DASH 本地代理（mpd 多清晰度）、弹幕、心跳上报、我的关注/动态/历史/UP 主等登录分区；
// 播放用 durl mp4 直链（fnval=1），和 Bili.js 一致。
import { Crypto } from 'assets://js/lib/cat.js';
import kids from './bili/kids.js';
import primary from './bili/primary.js';
import junior from './bili/junior.js';
import senior from './bili/senior.js';
import music from './bili/music.js';

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36';
const REF = 'https://www.bilibili.com';
const MIXIN = [46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
    37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52];
// ext.json 是 itv 包里的相对路径，App 里没有，按文件名映射到打包的分类数据
const BUNDLED = { '少儿教育.json': kids, '小学课堂.json': primary, '初中课堂.json': junior, '高中课堂.json': senior };
// ext.n 对应 Java homeContent 里写死的分类；本配置只用到哔哩音乐
const NAMED = { 哔哩音乐: music };

let cookie = '', mixinKey = '', homeJson = { class: [], filters: {} };

const strip = s => String(s || '').replace(/<[^>]+>/g, '').replace(/&quot;/g, '"').replace(/&amp;/g, '&');
const https = u => (u && u.startsWith('//') ? 'https:' + u : u || '');

function get(url) {
    const r = req(url, { headers: { 'User-Agent': UA, Referer: REF, Cookie: cookie }, timeout: 15000 });
    try { return JSON.parse(r.content || '{}'); } catch { return {}; }
}

function setMixin(img, sub) {
    const raw = (img || '') + (sub || '');
    if (raw.length >= 64) mixinKey = MIXIN.map(i => raw[i]).join('').slice(0, 32);
}

// WBI 签名：参数加 wts 后按 key 排序，去掉 !'()* 再拼 query，md5(query + mixinKey)
function wbi(params) {
    if (!mixinKey) {
        const img = get('https://api.bilibili.com/x/web-interface/nav').data?.wbi_img || {};
        const key = n => (n || '').split('/').pop().split('.')[0];
        setMixin(key(img.img_url), key(img.sub_url));
    }
    const p = { ...params, wts: Math.floor(Date.now() / 1000) };
    const q = Object.keys(p).sort().map(k => `${encodeURIComponent(k)}=${encodeURIComponent(String(p[k]).replace(/[!'()*]/g, ''))}`).join('&');
    return q + '&w_rid=' + Crypto.MD5(q + mixinKey).toString();
}

// 搜索接口没有 buvid3 会 -412，匿名时先领一个
function ensureBuvid() {
    if (/buvid3=/.test(cookie)) return;
    const b = get('https://api.bilibili.com/x/frontend/finger/spi').data?.b_3;
    if (b) cookie = (cookie ? cookie + '; ' : '') + 'buvid3=' + b;
}

// ext.cookie 是 cookie 文件地址（itv: http://127.0.0.1:9978/file/TVBox/bili_cookie.txt）或 cookie 串；
// 文件内容是 {"cookie": "...", "wbiImg": "...", "wbiSub": "..."} 或纯 cookie 串
function loadCookie(src) {
    if (!src) return;
    let text = /^https?:\/\//.test(src) ? (req(src, { timeout: 5000 }).content || '') : src;
    text = text.trim();
    if (text.startsWith('{')) {
        try {
            const j = JSON.parse(text);
            setMixin(j.wbiImg, j.wbiSub);
            text = j.cookie || '';
        } catch { text = ''; }
    }
    cookie = text.split(/[;\n]/).map(s => s.trim()).filter(s => s.includes('=')).join('; ');
}

function loadHome(cfg) {
    if (NAMED[cfg.n]) return NAMED[cfg.n];
    const src = cfg.json || '';
    const hit = BUNDLED[src.split('/').pop()];
    if (hit) return hit;
    if (/^https?:\/\//.test(src)) {
        try { return JSON.parse(req(src, { timeout: 10000 }).content || ''); } catch {}
    }
    return { class: [], filters: {} };
}

const vod = v => ({ vod_id: String(v.aid || v.id), vod_name: strip(v.title), vod_pic: https(v.pic), vod_remarks: v.duration || '' });

export default {
    init(ext) {
        const cfg = typeof ext === 'string' ? (ext.trim().startsWith('{') ? JSON.parse(ext) : {}) : (ext || {});
        cookie = ''; mixinKey = '';
        loadCookie(cfg.cookie);
        homeJson = loadHome(cfg);
    },

    home(filter) { return JSON.stringify(homeJson); },

    homeVod() {
        const d = get('https://api.bilibili.com/x/web-interface/popular?ps=20').data || {};
        return JSON.stringify({ list: (d.list || []).map(v => ({ ...vod(v), vod_remarks: '' })) });
    },

    category(tid, pg, filter, extend) {
        const e = extend || {};
        ensureBuvid();
        const keyword = e.tid ? tid + ' ' + e.tid : tid;
        const n = parseInt(pg) || 1;
        const d = get('https://api.bilibili.com/x/web-interface/wbi/search/type?' + wbi({
            search_type: 'video', keyword, order: e.order || 'totalrank', duration: e.duration || '0', page: n,
        })).data || {};
        const list = (d.result || []).map(vod);
        return JSON.stringify({ list, page: n, pagecount: d.numPages || (list.length ? n + 1 : n) });
    },

    detail(id) {
        const d = get('https://api.bilibili.com/x/web-interface/view?aid=' + id).data || {};
        return JSON.stringify({
            list: [{
                vod_id: id, vod_name: d.title, vod_pic: https(d.pic), type_name: d.tname,
                vod_director: d.owner?.name || '', vod_content: d.desc || '',
                vod_remarks: Math.floor((d.duration || 0) / 60) + '分鐘',
                vod_play_from: 'B站',
                vod_play_url: (d.pages || []).map(p => p.part + '$' + id + '_' + p.cid).join('#'),
            }],
        });
    },

    search(key, quick, pg) { return this.category(key, pg || '1', false, {}); },

    play(flag, id, flags) {
        const [avid, cid] = id.split('_');
        const d = get('https://api.bilibili.com/x/player/wbi/playurl?' + wbi({ avid, cid, qn: 116, fnval: 1, fourk: 1, platform: 'html5', high_quality: 1 })).data || {};
        return JSON.stringify({ parse: 0, url: (d.durl || [])[0]?.url || '', header: { 'User-Agent': UA, Referer: REF } });
    },
};
