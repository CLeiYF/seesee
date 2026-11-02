// 内置爱盼，对应 itv 单线路包 custom_spider_modified.jar 的 csp_AiPan。
// 站点 aipan.me 的 JSON 接口；详情 panLinks 为网盘分享链接，交给 pan/cloud.js 列目录。
import { seedCreds, playFrom, playUrl, play } from './pan/cloud.js';

const API = 'https://www.aipan.me/api/movies';
const HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36',
    Referer: 'https://www.aipan.me/',
    Accept: 'application/json, text/plain, */*',
};
// 同单线路包 config.json 的 panOrder
const PAN_ORDER = ['pan.baidu.com', 'drive.uc.cn', 'pan.quark.cn', 'pan.xunlei.com', 'guangyapan.com', 'cloud.189.cn', '123pan|123684|123865|123912', 'aliyundrive.com|alipan.com', 'caiyun.139.com'];

const get = path => { try { return JSON.parse(req(API + path, { headers: HEADERS, timeout: 15000 }).content || '{}'); } catch { return {}; } };
const panRank = u => { const i = PAN_ORDER.findIndex(p => p.split('|').some(x => u.includes(x))); return i < 0 ? 99 : i; };
const vod = (m, id = m.id) => ({ vod_id: String(id || ''), vod_name: m.title || '', vod_pic: m.cover || '', vod_remarks: '评分：' + (m.rate || '0') });

export default {
    init(ext) {
        const cfg = typeof ext === 'string' ? (ext.trim().startsWith('{') ? JSON.parse(ext) : {}) : (ext || {});
        seedCreds(cfg);
    },

    // type_id 即列表接口的查询串
    home() {
        return JSON.stringify({ class: [['top250=1', 'TOP250'], ['sort=latest', '最新发布'], ['imdbMin=8&sort=latest', '高分精选']].map(([type_id, type_name]) => ({ type_id, type_name })) });
    },

    homeVod() {
        // hero 项只有页面 url，id 取最后一段
        const list = (get('/home').hero || []).map(m => vod(m, String(m.url || '').split('/').pop()));
        return JSON.stringify({ list });
    },

    category(tid, pg) {
        const r = get(`/list?${tid}&page=${pg}&pageSize=30`);
        const limit = r.pageSize || 0, total = r.total || 0;
        return JSON.stringify({ list: (r.movies || []).map(m => vod(m)), page: r.page || 0, pagecount: limit > 0 ? Math.floor((total - 1) / limit) + 1 : 1, limit, total });
    },

    detail(id) {
        const r = get('/detail/' + id);
        const links = (r.panLinks || []).map(x => x.url).filter(Boolean).sort((a, b) => panRank(a) - panRank(b));
        return JSON.stringify({
            list: [{
                vod_id: id, vod_name: r.title || '', vod_year: String(r.year || ''), vod_area: r.region || '',
                vod_director: (r.directors || []).join(','), vod_actor: (r.actors || []).join(','),
                vod_remarks: '评分：' + (r.imdbRating || '0'),
                vod_content: String(r.synopsis || '').replace(/\[.*?\]/g, '').replace(/ /g, ''),
                vod_play_from: playFrom(links), vod_play_url: playUrl(links).replace(/\[\d{4,8}\]/g, ''),
            }],
        });
    },

    search(key) {
        return JSON.stringify({ list: (get('/search?q=' + encodeURIComponent(key)).movies || []).map(m => vod(m)) });
    },

    play(flag, id) { return play(flag, id); },
};
