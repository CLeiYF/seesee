// 内置双星，对应 itv 单线路包 custom_spider_modified.jar 的 csp_ShuangXing。
// 详情页 .dlipp-dl-btn 的 href 为网盘分享链接，交给 pan/cloud.js 列目录。
import { load } from 'assets://js/lib/cat.js';
import { seedCreds, playFrom, playUrl, play } from './pan/cloud.js';

const HOST = 'https://1.star2.cn';
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36';
// 同单线路包 config.json 的 panOrder
const PAN_ORDER = ['pan.baidu.com', 'drive.uc.cn', 'pan.quark.cn', 'pan.xunlei.com', 'guangyapan.com', 'cloud.189.cn', '123pan|123684|123865|123912', 'aliyundrive.com|alipan.com', 'caiyun.139.com'];
let cookie = '';

const headers = () => ({ 'User-Agent': UA, Referer: HOST, Cookie: cookie });
const get = path => req(HOST + path, { headers: headers(), timeout: 15000 }).content || '';
const panRank = u => { const i = PAN_ORDER.findIndex(p => p.split('|').some(x => u.includes(x))); return i < 0 ? 99 : i; };

// 同 Java b.o()：不跟随跳转取首页 Set-Cookie，只留 name=value（多条 Set-Cookie 被 ", " 合并）
function fetchCookie() {
    const h = req(HOST, { headers: headers(), timeout: 15000, redirect: 0 }).headers || {};
    const raw = String(h['set-cookie'] || h['Set-Cookie'] || '');
    return [...raw.matchAll(/(?:^|,\s*)([^=;,\s]+=[^;,]*)/g)].map(m => m[1] + '; ').join('');
}

// ul.erx-list 的每个 li.item；标题去掉【…】标签（未闭合则删到末尾）
function vods(html, withDate) {
    const $ = load(html);
    return $('ul.erx-list').first().find('li.item').toArray().map(e => {
        const a = $(e).find('a').first();
        const name = (a.text() || '').replace(/【[^】]*】/g, '').replace(/【.*$/, '');
        return { vod_id: a.attr('href') || '', vod_name: name, vod_pic: '', vod_remarks: withDate ? $(e).find('span.erx-num-font.time').first().text() : '' };
    }).filter(v => v.vod_id && v.vod_name);
}

export default {
    init(ext) {
        const cfg = typeof ext === 'string' ? (ext.trim().startsWith('{') ? JSON.parse(ext) : {}) : (ext || {});
        seedCreds(cfg);
        cookie = fetchCookie();
    },

    home() {
        const ids = ['dj', 'ju', 'zy', 'mv', 'rh', 'ym', 'wj', 'dm'], names = ['短剧', '国剧', '综艺', '电影', '韩日', '英美', '外剧', '动漫'];
        return JSON.stringify({ class: ids.map((type_id, i) => ({ type_id, type_name: names[i] })), filters: {} });
    },

    homeVod() { return JSON.stringify({ list: [] }); },

    category(tid, pg) {
        const list = vods(get(`/${tid}_${pg}`), false);
        if (!list.length) return JSON.stringify({ list, page: 1, pagecount: 1, limit: 20, total: 0 });
        return JSON.stringify({ list, page: parseInt(pg) || 1, pagecount: 100, limit: 20, total: 20 });
    },

    detail(id) {
        const html = get(id);
        if (!html) return JSON.stringify({ msg: '获取详情页失败' });
        const $ = load(html);
        const links = $('.dlipp-dl-btn').toArray().map(e => $(e).attr('href') || '').filter(Boolean)
            .sort((a, b) => panRank(a) - panRank(b));
        const vod = { vod_id: id, vod_name: $('h1').first().text(), vod_pic: '', vod_remarks: '', vod_content: '' };
        if (links.length) Object.assign(vod, { vod_play_from: playFrom(links), vod_play_url: playUrl(links).replace(/\[\d{4,8}\]/g, '') });
        return JSON.stringify({ list: [vod] });
    },

    search(key) {
        return JSON.stringify({ list: vods(get('/search/?keyword=' + encodeURIComponent(key)), true) });
    },

    play(flag, id) { return play(flag, id); },
};
