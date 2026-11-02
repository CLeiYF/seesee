// 内置移动，对应 itv 单线路包 custom_spider_modified.jar 的 csp_Yidong4K。
// vidsite.cloudseekr.com 的 JSON 接口；详情 resUrl 为移动云盘（139）分享链接，交给 pan/cloud.js（yidong.js）列目录。
import { Crypto } from 'assets://js/lib/cat.js';
import { seedCreds, playFrom, playUrl, play } from './pan/cloud.js';

const API = 'https://vidsite.cloudseekr.com/vidsite/vs/';
// ponytail: 不带 Java 里的 Host/Connection/Accept-Encoding，由 HTTP 栈自行处理
const HEADERS = {
    Origin: 'https://vidsite.cloudseekr.com',
    Accept: 'application/json, text/plain, */*',
    'Cache-Control': 'no-cache',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36',
    Referer: 'https://vidsite.cloudseekr.com/vid/app/',
    Pragma: 'no-cache',
    'Content-Type': 'application/json; charset=utf-8',
};
// 同 Java b()：每次启动生成一个设备指纹
let fprint = '';

function post(path, body) {
    try { return JSON.parse(req(API + path, { method: 'post', headers: HEADERS, data: JSON.stringify(body), timeout: 15000 }).content || '{}'); } catch { return {}; }
}

function page(body, pg) {
    const r = post('qryPageColumnVideo', { cateIdList: [0, 0, 0], pageIndex: 1, pageSize: 9, ...body });
    if (r.code !== '000000') return { list: [], page: 1, pagecount: 1, limit: 9, total: 0 };
    const d = r.data || {};
    const list = (d.list || []).map(v => ({ vod_id: String(v.id), vod_name: v.title || '', vod_pic: v.appCoverUrl || '', vod_remarks: '' }));
    return { list, page: pg, pagecount: d.pages || 1, limit: 9, total: d.total || 0 };
}

export default {
    init(ext) {
        const cfg = typeof ext === 'string' ? (ext.trim().startsWith('{') ? JSON.parse(ext) : {}) : (ext || {});
        seedCreds(cfg);
        if (!fprint) fprint = Crypto.MD5('AiNewYiDong4K_' + Date.now() + '_' + Math.random()).toString();
    },

    home() {
        return JSON.stringify({ class: [['1', '电影'], ['2', '电视剧'], ['3', '动漫']].map(([type_id, type_name]) => ({ type_id, type_name })), filters: {} });
    },

    homeVod() { return JSON.stringify({ list: [] }); },

    category(tid, pg) {
        const p = parseInt(pg) || 1;
        return JSON.stringify(page({ columnId: parseInt(tid), pageIndex: p }, p));
    },

    detail(id) {
        const body = { videoId: parseInt(id), fprint };
        // 同 Java：先登记访问，成功后才取详情
        if (post('addAccessRecord', body).code !== '000000') return JSON.stringify({ list: [] });
        const r = post('qryVideoDetail', body);
        if (r.code !== '000000' || !r.data) return JSON.stringify({ list: [] });
        const d = r.data;
        const links = d.resUrl ? [d.resUrl] : [];
        return JSON.stringify({
            list: [{
                vod_id: String(d.id), vod_name: d.title || '', vod_pic: d.appCoverUrl || '',
                vod_content: String(d.remark || '').replace(/\[.*?\]/g, '').replace(/ /g, ''),
                type_name: JSON.stringify(d.cateNameList || []),
                vod_play_from: playFrom(links), vod_play_url: playUrl(links).replace(/\[\d{4,8}\]/g, ''),
            }],
        });
    },

    search(key) {
        return JSON.stringify(page({ columnId: 0, searchKey: key }, 1));
    },

    play(flag, id) { return play(flag, id); },
};
