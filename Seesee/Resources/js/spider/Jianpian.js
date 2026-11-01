// 内置荐片，对应 jar 的 csp_Jianpian（AndroidCatVodSpider/spider/Jianpian.java）。
// 域名经 alidns TXT 记录动态解析（wangerniu.<域名>），取首个 appAuthConfig 可用的。
// ext 可选：筛选配置的 URL 或 JSON（jianpian.json 格式）；为空时用内置。
const DNS = 'https://dns.alidns.com/resolve?name=swrdsfeiujo25sw.cc&type=TXT';
const UA = 'Mozilla/5.0 (Linux; Android 9; V2196A Build/PQ3A.190705.08211809; wv) AppleWebKit/537.36 (KHTML, like Gecko) '
    + 'Version/4.0 Chrome/91.0.4472.114 Mobile Safari/537.36;webank/h5face;webank/1.0;netType:NETWORK_WIFI;appVersion:416;packageName:com.jp3.xg3';
const CLASSES = [['1', '电影'], ['2', '电视剧'], ['3', '动漫'], ['4', '综艺'], ['50', '纪录片'], ['99', 'Netflix']];
const opt = (key, name, pairs) => ({ key, name, value: pairs.map(([n, v]) => ({ n, v })) });
const BASE_FILTER = [
    opt('area', '地区', [['全部', '0'], ['国产', '1'], ['中国香港', '3'], ['中国台湾', '6'], ['美国', '5'], ['韩国', '18'], ['日本', '2']]),
    opt('year', '年份', [['全部', '0'], ['2024', '119'], ['2023', '153'], ['2022', '101'], ['2021', '118'], ['2020', '16'], ['2019', '7'], ['2018', '2'], ['2017', '3'], ['2016', '22']]),
    opt('by', '排序', [['更新', 'updata'], ['热门', 'hot'], ['评分', 'rating']]),
];
const FILTERS = { 1: BASE_FILTER, 2: BASE_FILTER, 3: BASE_FILTER, 4: BASE_FILTER };

let ext = '', host = '', img = '';

function getJson(url, headers) {
    return JSON.parse(req(url, { headers: headers || {}, timeout: 15000 }).content || '{}');
}

function headers() { return { 'User-Agent': UA, 'Referer': host }; }

function resolve() {
    if (host) return;
    const answer = (getJson(DNS).Answer || [])[0];
    const domains = ((answer && answer.data) || '').replace(/"/g, '').split(',');
    for (const d of domains) {
        if (!d.trim()) continue;
        const h = 'https://wangerniu.' + d.trim();
        try {
            const cfg = getJson(h + '/api/appAuthConfig');
            if (cfg.data && cfg.data.imgDomain) { host = h; img = cfg.data.imgDomain; return; }
        } catch (e) { /* 换下一个域名 */ }
    }
    throw new Error('荐片：无可用域名');
}

function api(path) { resolve(); return getJson(host + path, headers()); }

function pic(it) { const p = it.thumbnail || it.path || ''; return p ? 'http://' + img + p : ''; }

function vod(it) {
    return {
        vod_id: String(it.id ?? ''), vod_name: it.title || '', vod_pic: pic(it),
        vod_remarks: it.mask || (it.playlist && it.playlist.title) || '',
    };
}

function names(items) {
    return (items || []).map(v => (v && typeof v === 'object') ? (v.title || v.name || '') : String(v)).join(' ');
}

export default {
    init(e) { ext = typeof e === 'string' ? e.trim() : (e ? JSON.stringify(e) : ''); },

    home(filter) {
        const res = { class: CLASSES.map(([type_id, type_name]) => ({ type_id, type_name })) };
        if (filter) res.filters = ext.startsWith('http') ? getJson(ext) : (ext ? JSON.parse(ext) : FILTERS);
        return JSON.stringify(res);
    },

    homeVod() {
        const data = api('/api/slide/list?pos_id=88').data || [];
        return JSON.stringify({ list: data.map(it => ({ vod_id: String(it.jump_id ?? ''), vod_name: it.title || '', vod_pic: pic(it) })) });
    },

    category(tid, pg, filter, extend) {
        extend = extend || {};
        let list;
        if (['50', '99', '111'].includes(tid)) {
            list = (api('/api/dyTag/list?category_id=' + tid + '&page=' + pg).data || []).flatMap(d => (d.dataList || []).map(vod));
        } else {
            const q = '/api/crumb/list?fcate_pid=' + tid + '&area=' + (extend.area || '0') + '&year=' + (extend.year || '0')
                + '&type=0&sort=' + (extend.by || 'updata') + '&page=' + pg + '&category_id=';
            list = (api(q).data || []).map(vod);
        }
        return JSON.stringify({ list, page: parseInt(pg) });
    },

    detail(id) {
        const d = api('/api/video/detailv2?id=' + id).data || {};
        const srcs = d.source_list_source || [];
        return JSON.stringify({
            list: [Object.assign(vod(d), {
                vod_year: String(d.year || ''), vod_area: d.area || '', type_name: names(d.types),
                vod_actor: names(d.actors), vod_director: names(d.directors),
                vod_content: (d.description || '').replace(/　/g, ''),
                vod_play_from: srcs.map(s => s.name || '').join('$$$'),
                // ponytail: Java 把 ftp 改写为迅雷协议；App 不支持迅雷，保持原样（这类线路会播放失败）
                vod_play_url: srcs.map(s => (s.source_list || []).map(x => (x.source_name || '') + '$' + (x.url || '')).join('#')).join('$$$'),
            })],
        });
    },

    search(key, quick, pg) {
        const data = api('/api/v2/search/videoV2?key=' + encodeURIComponent(key) + '&category_id=88&page=' + (pg || 1) + '&pageSize=20');
        return JSON.stringify({ list: (data.data || []).map(vod), page: parseInt(pg || 1) });
    },

    play(flag, id, flags) {
        resolve();
        return JSON.stringify({ parse: 0, url: id, header: headers() });
    },
};
