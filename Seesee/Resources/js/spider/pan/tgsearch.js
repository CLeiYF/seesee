// TgSearch* 共用实现（对应 spider/TgSearchQuark.java 等，五个 Java 类代码相同）：pansou 聚合搜索 API，
// 结果 vod_id 为分享链接，detail 交给 cloud.js 列目录。
// ext：API 地址字符串，或 JSON { api_urls: [...], siteurl: {域名片段: 名称}, sources: [名称...], cookie, uccookie, tianyicookie, token }，
// 多段用 ### 分隔取第一段。
import { shareDetail, play, isShare, seedCreds } from './cloud.js';
import { http, parseJson, qs, CHROME } from './common.js';

const DEFAULT_API = 'https://so.252035.xyz/api/search';
const DOMAINS = { alipan: '阿里', aliyundrive: '阿里', quark: '夸克', '115cdn': '115', 'baidu.com': '百度', uc: 'UC',
    '189.cn': '天翼', '139.com': '移动', '123': '123盘' };

/** cloudTypes：pansou 的 cloud_types 参数（如 'quark'），为空则不限 */
export function tgSearch(cloudTypes) {
    let apis = [], domains = { ...DOMAINS }, sources = [];
    const mapSource = (url, orig) => Object.entries(domains).find(([k]) => url.includes(k))?.[1] || orig;

    return {
        init(e) {
            apis = []; domains = { ...DOMAINS }; sources = [];
            seedCreds(e);   // ext 里也可带 cookie / uccookie / tianyicookie / token
            const cfg = (typeof e === 'string' ? e : e ? JSON.stringify(e) : '').split('###')[0].trim();
            if (/^https?:\/\//.test(cfg)) apis.push(cfg);
            else if (cfg) {
                try {
                    const o = JSON.parse(cfg);
                    for (const u of o.api_urls || []) if (/^https?:\/\//.test(u) && !apis.includes(u)) apis.push(u);
                    for (const [k, v] of Object.entries(o.siteurl || {})) if (k && v && !(k in domains)) domains[k] = String(v);
                    sources = (o.sources || []).filter(Boolean).map(String);
                } catch { /* 用默认 */ }
            }
            if (!apis.length) apis.push(DEFAULT_API);
        },
        home() { return JSON.stringify({ class: [] }); },
        homeVod() { return JSON.stringify({ list: [] }); },
        category() { return JSON.stringify({ list: [] }); },
        detail(id) { return JSON.stringify({ list: [shareDetail(id)] }); },
        search(key, quick, pg) {
            key = String(key || '').trim();
            if (!key || Number(pg || 1) > 1) return JSON.stringify({ list: [] });   // pansou 一次返回全部
            const params = { kw: key, res: 'merge', src: 'all' };
            if (cloudTypes) params.cloud_types = cloudTypes;
            // pansou 公共实例被限流时会 403/302/超时，或假装无结果（total: 0），每个地址最多试两次
            let empty = null;
            // App 里单次 JS 调用上限 30s，整体留 25s 预算
            const deadline = Date.now() + 25000;
            for (const api of apis.flatMap(a => [a, a])) {
                const left = deadline - Date.now();
                if (left < 3000) break;
                const r = http(api + (api.includes('?') ? '&' : '?') + qs(params), { headers: { 'User-Agent': CHROME }, timeout: Math.min(15000, left) });
                let j;
                try { j = parseJson(r.content); } catch { continue; }
                if (!j || j.code !== 0 || !j.data) continue;
                const merged = j.data.merged_by_type || {};   // 无结果时只有 total: 0
                const list = [];
                for (const items of Object.values(merged)) {
                    for (const it of Array.isArray(items) ? items : []) {
                        const url = it && it.url;
                        if (!url || !isShare(url)) continue;   // 只留能列目录的网盘
                        const link = it.password && !/[?&]pwd=/.test(url) ? url + (url.includes('?') ? '&' : '?') + 'pwd=' + it.password : url;
                        const orig = it.source || '未知来源', name = mapSource(url, orig);
                        if (sources.length && !sources.includes(name)) continue;
                        list.push({ vod_id: link, vod_name: it.note || '未命名资源', vod_pic: (it.images || [])[0] || '',
                            vod_remarks: `${name} (${orig})` });
                    }
                }
                const out = JSON.stringify({ page: 1, pagecount: 1, total: list.length, list });
                if (list.length) return out;
                empty = out;
            }
            return empty || JSON.stringify({ list: [], msg: '无法连接到任何搜索API' });
        },
        play(flag, id) { return play(flag, id); },
    };
}
