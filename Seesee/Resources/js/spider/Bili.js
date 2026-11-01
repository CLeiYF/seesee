// 内置哔哩哔哩，对应 itv 配置里的 ./python/bilibili_hipy.py（哔哩大会员）。
// ponytail: 只做点播主干（推荐/热门/排行/PGC 分区、搜索、详情、mp4 直链）。
// 跳过了原 py 的扫码登录、DASH 本地代理（4K/杜比）、直播、动态/收藏/关注、心跳；要用再加。
import { Crypto } from 'assets://js/lib/cat.js';

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36';
const REF = 'https://www.bilibili.com';
const MIXIN = [46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
    37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52];
// 分类：rcmd/popular/rank 为 UGC；pgc_N 为 PGC 索引（season_type）
const CLASSES = [['rcmd', '推荐'], ['popular', '热门'], ['rank', '排行榜'], ['pgc_1', '番剧'], ['pgc_4', '国创'],
    ['pgc_2', '电影'], ['pgc_5', '电视剧'], ['pgc_3', '纪录片']];

let cookie = '', mixinKey = '';

const strip = s => String(s || '').replace(/<[^>]+>/g, '').replace(/&quot;/g, '"').replace(/&amp;/g, '&');
const https = u => (u && u.startsWith('//') ? 'https:' + u : u || '');
const dur = s => (s ? `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}` : '');

function get(url) {
    const r = req(url, { headers: { 'User-Agent': UA, Referer: REF, Cookie: cookie }, timeout: 15000 });
    return JSON.parse(r.content || '{}');
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

function setMixin(img, sub) {
    const raw = (img || '') + (sub || '');
    if (raw.length >= 64) mixinKey = MIXIN.map(i => raw[i]).join('').slice(0, 32);
}

// 搜索接口没有 buvid3 会 -412，匿名时先领一个
function ensureBuvid() {
    if (/buvid3=/.test(cookie)) return;
    const b = get('https://api.bilibili.com/x/frontend/finger/spi').data?.b_3;
    if (b) cookie = (cookie ? cookie + '; ' : '') + 'buvid3=' + b;
}

const ugc = v => ({ vod_id: v.bvid, vod_name: strip(v.title), vod_pic: https(v.pic), vod_remarks: typeof v.duration === 'number' ? dur(v.duration) : (v.duration || '') });
const pgc = v => ({ vod_id: 'ss' + v.season_id, vod_name: strip(v.title), vod_pic: https(v.cover), vod_remarks: v.index_show || v.badge || '' });

// ext.cookie 可以是 cookie 文件地址（itv: http://127.0.0.1:9978/file/TVBox/bili_cookie.txt）或 cookie 串；
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

export default {
    init(ext) {
        const cfg = typeof ext === 'string' ? (ext.trim().startsWith('{') ? JSON.parse(ext) : {}) : (ext || {});
        cookie = ''; mixinKey = '';
        loadCookie(cfg.cookie);
    },

    home(filter) {
        return JSON.stringify({ class: CLASSES.map(([type_id, type_name]) => ({ type_id, type_name })) });
    },

    homeVod() {
        const d = get('https://api.bilibili.com/x/web-interface/popular?pn=1&ps=20').data || {};
        return JSON.stringify({ list: (d.list || []).map(ugc) });
    },

    category(tid, pg, filter, extend) {
        const n = parseInt(pg) || 1;
        let list = [];
        if (tid === 'rcmd') {
            const d = get('https://api.bilibili.com/x/web-interface/wbi/index/top/feed/rcmd?' + wbi({ fresh_idx: n, ps: 20, fresh_type: 4 })).data || {};
            list = (d.item || []).filter(v => v.bvid).map(ugc);
        } else if (tid === 'popular') {
            list = ((get(`https://api.bilibili.com/x/web-interface/popular?pn=${n}&ps=20`).data || {}).list || []).map(ugc);
        } else if (tid === 'rank') {
            list = n > 1 ? [] : ((get('https://api.bilibili.com/x/web-interface/ranking/v2?rid=0&type=all').data || {}).list || []).map(ugc);
        } else if (tid.startsWith('pgc_')) {
            const t = tid.slice(4);
            const d = get(`https://api.bilibili.com/pgc/season/index/result?type=1&season_type=${t}&page=${n}&order=2&season_status=-1&pagesize=20`).data || {};
            list = (d.list || []).map(pgc);
        }
        return JSON.stringify({ list, page: n, pagecount: list.length ? n + 1 : n });
    },

    detail(id) {
        if (id.startsWith('ss') || id.startsWith('ep')) return JSON.stringify({ list: [season(id)] });
        const d = get('https://api.bilibili.com/x/web-interface/view?bvid=' + id).data || {};
        const pages = d.pages || [];
        return JSON.stringify({
            list: [{
                vod_id: id, vod_name: d.title, vod_pic: https(d.pic), type_name: d.tname,
                vod_actor: d.owner?.name || '', vod_remarks: dur(d.duration), vod_content: d.desc || '',
                vod_year: d.pubdate ? String(new Date(d.pubdate * 1000).getFullYear()) : '',
                vod_play_from: 'B站',
                vod_play_url: pages.map(p => (pages.length > 1 ? p.part : d.title) + '$' + d.aid + '_' + p.cid).join('#'),
            }],
        });
    },

    search(key, quick, pg) {
        ensureBuvid();
        const n = parseInt(pg) || 1;
        const out = [];
        // 先影视/番剧再普通视频，和原 py 的 searchTypes 顺序一致
        for (const type of ['media_ft', 'media_bangumi', 'video']) {
            if (type !== 'video' && n > 1) continue;
            const d = get('https://api.bilibili.com/x/web-interface/wbi/search/type?' + wbi({ search_type: type, keyword: key, page: n })).data || {};
            for (const v of d.result || []) out.push(type === 'video' ? ugc({ ...v, pic: v.pic, duration: v.duration }) : pgc(v));
        }
        return JSON.stringify({ list: out, page: n });
    },

    play(flag, id, flags) {
        const [aid, cid, ep] = id.split('_');
        const base = ep
            ? `https://api.bilibili.com/pgc/player/web/playurl?ep_id=${ep}&cid=${cid}&qn=116&fnval=1&fourk=1`
            : 'https://api.bilibili.com/x/player/wbi/playurl?' + wbi({ avid: aid, cid, qn: 116, fnval: 1, fourk: 1, platform: 'html5', high_quality: 1 });
        const j = get(base);
        const d = j.data || j.result || {};
        const url = (d.durl || [])[0]?.url || '';
        return JSON.stringify({ parse: 0, url, header: { 'User-Agent': UA, Referer: REF } });
    },
};

// 番剧/影视：ss<seasonId> 或 ep<epId>，正片放第一条线路，预告花絮等 section 另开线路
function season(id) {
    const q = id.startsWith('ss') ? 'season_id=' + id.slice(2) : 'ep_id=' + id.slice(2);
    const r = get('https://api.bilibili.com/pgc/view/web/season?' + q).result || {};
    const ep = e => (e.show_title || e.long_title || e.title || '').replace(/\$|#/g, ' ') + '$' + e.aid + '_' + e.cid + '_' + e.id;
    const froms = [], urls = [];
    if ((r.episodes || []).length) { froms.push('B站'); urls.push(r.episodes.map(ep).join('#')); }
    for (const s of r.section || []) {
        if ((s.episodes || []).length) { froms.push(s.title || '其他'); urls.push(s.episodes.map(ep).join('#')); }
    }
    return {
        vod_id: id, vod_name: r.title, vod_pic: https(r.cover), type_name: r.type_name || '',
        vod_area: (r.areas || []).map(a => a.name).join(' '), vod_year: (r.publish?.pub_time || '').slice(0, 4),
        vod_remarks: r.new_ep?.desc || '', vod_actor: (r.actors || '').replace(/\n/g, ' '), vod_content: r.evaluate || '',
        vod_play_from: froms.join('$$$'), vod_play_url: urls.join('$$$'),
    };
}
