// 内置童趣，对应 itv 单线路包 custom_spider_modified.jar 的 csp_TongQu（播视网 boosj.com 儿童频道）。
// 列表页正则抽取；播放走 gslb 调度接口拿 mp4 直链。
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36';
const NAMES = ['全部', '辅食', '动画', '儿童舞蹈', '少儿英语', '儿童歌曲', '才艺', '播视自制', '故事', '亲子教育', '美术', '其他', '儿童游戏', '识物', '绘本', '古诗', '科普', '儿童玩具', '播视童趣儿童玩具'];
const IDS = ['all', '28', '582', '3364', '3366', '3367', '3622', '3782', '3822', '3842', '4402', '4583', '4762', '4842', '4843', '4844', '4845', '5102', '5142'];
const FILTERS = [
    { key: 'area', name: '年龄段', value: [['全部', ''], ['6岁以上', '?p367=370'], ['3~6岁', '?p367=369'], ['0~3岁', '?p367=368']].map(([n, v]) => ({ n, v })) },
    { key: 'by', name: '排序', value: [['全部', ''], ['最新发布', 'lately'], ['最多播放', 'pop'], ['最多评论', 'view']].map(([n, v]) => ({ n, v })) },
];

function get(url, referer) {
    return req(url, { headers: { 'User-Agent': UA, Referer: referer || 'https://www.boosj.com/' }, timeout: 15000 }).content || '';
}

const https = u => (u.startsWith('//') ? 'https:' + u : u);
const m1 = (re, s, d = '') => (s.match(re) || [, d])[1];

// 按块正则抽取，块内找 id/标题/封面/备注，id 去重
function parse(html, blockRe, pick) {
    const seen = new Map();
    for (const [, b] of html.matchAll(blockRe)) {
        const id = m1(/boosj\.com\/(\d+)\.html/, b);
        if (id && !seen.has(id)) seen.set(id, { vod_id: id, ...pick(b, id) });
    }
    return [...seen.values()];
}

export default {
    init(ext) {},

    home(filter) {
        const filters = {};
        for (const id of IDS) filters[id] = FILTERS;
        return JSON.stringify({ class: IDS.map((type_id, i) => ({ type_id, type_name: NAMES[i] })), filters });
    },

    homeVod() {
        const list = parse(get('https://www.boosj.com/baby/'), /<div class="pubpic">([\s\S]*?)<\/div>\s*<\/div>/gi, (b, id) => ({
            vod_name: m1(/title="([^"]+)"/, b, id).trim(), vod_pic: https(m1(/(?:src|data-original)="([^"]+)"/, b)), vod_remarks: '推荐',
        }));
        return JSON.stringify({ list });
    },

    category(tid, pg, filter, extend) {
        const e = extend || {}, by = e.by || '', n = parseInt(pg) || 1;
        const t = !tid || tid === 'all' || tid === '_' ? '' : tid.replace(/^_/, '');
        // search_res_3362__{tid}_{pg}_{by}.html{area}；第 1 页 pg 为空，全部分类首页多两个 _
        const tail = n === 1 && !by ? (t ? '__.html' : '____.html') : `_${n === 1 ? '' : n}_${by}.html`;
        const html = get(`https://www.boosj.com/search_res_3362__${t}${tail}${e.area || ''}`);
        const list = parse(html, /<div class="bj-col4">([\s\S]*?)<\/div>\s*<\/div>/gi, (b, id) => ({
            vod_name: m1(/<h3>[\s\S]*?title="([^"]+)"/, b, id).trim(),
            vod_pic: https(m1(/(?:data-original|src)="([^"]+)"/, b)),
            vod_remarks: m1(/icon_duration[\s\S]*?<span class="played">([^<]*)<\/span>/, b).trim(),
        }));
        return JSON.stringify({ list, page: n, pagecount: list.length ? n + 1 : n, limit: 24, total: 9999 });
    },

    detail(id) {
        const name = m1(/<h2 class="video_title">([^<]+)<\/h2>/, get(`https://www.boosj.com/${id}.html`)).trim() || id;
        return JSON.stringify({ list: [{ vod_id: id, vod_name: name, vod_pic: '', vod_remarks: '', vod_play_from: '童趣', vod_play_url: '播放$' + id }] });
    },

    search(key, quick, pg) {
        if (!key) return JSON.stringify({ list: [] });
        let j = {};
        try { j = JSON.parse(get('https://search.boosj.com/m_ajax?q=' + encodeURIComponent(key.trim()) + '&p=1&typeId=3362')); } catch {}
        const list = j.code === 200 ? (j.body?.result || []).map(v => ({ vod_id: String(v.id), vod_name: v.resourceName, vod_pic: v.imageUrl, vod_remarks: v.clickNumStr })) : [];
        return JSON.stringify({ list });
    },

    play(flag, id, flags) {
        const vid = m1(/(\d+)/, id);
        const referer = `https://www.boosj.com/${vid}.html`;
        let url = '';
        try {
            // ipv2.json 给出 gslb 调度地址和参数，原样（含 gslb 键）拼成 query，再加 _id
            const p = { ...JSON.parse(get('https://gslb.boosj.com/ipv2.json')), _id: vid };
            const q = Object.entries(p).map(([k, v]) => k + '=' + encodeURIComponent(String(v))).join('&');
            const body = get((p.gslb || 'https://gslb.boosj.com/gslbm') + '?' + q, referer);
            if (vid && body && !body.includes('Forbidden')) {
                const r = JSON.parse(body);
                url = r.url && r.t ? r.url + '?' + r.t : r.url || '';
            }
        } catch {}
        return JSON.stringify({ parse: 0, url, header: { 'User-Agent': UA, Referer: referer } });
    },
};
