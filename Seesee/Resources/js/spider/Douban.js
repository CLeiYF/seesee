// 内置豆瓣推荐源，对应 jar 的 csp_Douban / csp_DoubanLocal（AndroidCatVodSpider/spider/Douban.java）。
// 只做推荐：vod_id 为 "msearch:<豆瓣id>"，App 点击后转全局搜索。
// ext：筛选配置的 URL 或 JSON（douban.json 格式），为空时用下面的精简版。
const API = 'https://frodo.douban.com/api/v2';
const APIKEY = '?apikey=0ac44ae016490db2204ce0a042db2916';
const HEADERS = {
    'Host': 'frodo.douban.com',
    'Referer': 'https://servicewechat.com/wx2f9b06c1de1ccfca/84/page-frame.html',
    'User-Agent': 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/53.0.2785.143 Safari/537.36 MicroMessenger/7.0.9.501 NetType/WIFI MiniProgramEnv/Windows WindowsWechat',
};
const CHROME = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36';
const CLASSES = [['hot_gaia', '热门电影'], ['tv_hot', '热播剧集'], ['show_hot', '热播综艺'], ['movie', '电影筛选'],
    ['tv', '电视筛选'], ['rank_list_movie', '电影榜单'], ['rank_list_tv', '电视剧榜单']];
// 集合类分类：tid -> [筛选 key, 默认 collection]
const COLLECTIONS = {
    tv_hot: ['type', 'tv_hot'], show_hot: ['type', 'show_hot'],
    rank_list_movie: ['榜单', 'movie_real_time_hotest'], rank_list_tv: ['榜单', 'tv_real_time_hotest'],
};
const opt = (key, name, pairs) => ({ key, name, value: pairs.map(([n, v]) => ({ n, v: v ?? n })) });
// ponytail: 精简筛选，完整的靠 ext 指向 douban.json
const FILTERS = {
    hot_gaia: [opt('sort', '排序', [['热度', 'recommend'], ['最新', 'time'], ['评分', 'rank']]),
        opt('area', '地区', [['全部'], ['华语'], ['欧美'], ['韩国'], ['日本']])],
    tv_hot: [opt('type', '分类', [['综合', 'tv_hot'], ['国产剧', 'tv_domestic'], ['欧美剧', 'tv_american'], ['日剧', 'tv_japanese'], ['韩剧', 'tv_korean'], ['动画', 'tv_animation']])],
    show_hot: [opt('type', '分类', [['综合', 'show_hot'], ['国内', 'show_domestic'], ['国外', 'show_foreign']])],
    movie: [opt('类型', '类型', [['全部', ''], ['喜剧'], ['爱情'], ['动作'], ['科幻'], ['动画'], ['悬疑'], ['犯罪'], ['惊悚'], ['冒险']]),
        opt('sort', '排序', [['综合', 'T'], ['近期热度', 'U'], ['首映时间', 'R'], ['高分优先', 'S']])],
    tv: [opt('类型', '类型', [['全部', ''], ['电视剧'], ['综艺']]),
        opt('sort', '排序', [['综合', 'T'], ['近期热度', 'U'], ['首映时间', 'R'], ['高分优先', 'S']])],
    rank_list_movie: [opt('榜单', '榜单', [['实时热门电影', 'movie_real_time_hotest'], ['一周口碑电影', 'movie_weekly_best'], ['Top250', 'movie_top250']])],
    rank_list_tv: [opt('榜单', '榜单', [['实时热门剧集', 'tv_real_time_hotest'], ['华语口碑剧集', 'tv_chinese_best_weekly'], ['全球口碑剧集', 'tv_global_best_weekly']])],
};

let ext = '';

function getJson(url, headers) {
    const r = req(url, { headers: headers || {} });
    return JSON.parse(r.content || '{}');
}

function vods(items) {
    return (items || []).map(it => {
        const pic = (it.pic && it.pic.normal) || '';
        const rating = it.rating && it.rating.value;
        return {
            vod_id: 'msearch:' + (it.id || ''),
            vod_name: it.title || '',
            vod_pic: pic && pic + '@Referer=https://api.douban.com/@User-Agent=' + CHROME,
            vod_remarks: rating ? '评分：' + rating : '', // 0 表示暂无评分
        };
    });
}

function filters() {
    if (!ext) return FILTERS;
    if (ext.startsWith('http')) return getJson(ext);
    try { return JSON.parse(ext); } catch (e) { return FILTERS; }
}

export default {
    init(e) { ext = typeof e === 'string' ? e.trim() : (e ? JSON.stringify(e) : ''); },

    home(filter) {
        const items = getJson(API + '/subject_collection/subject_real_time_hotest/items' + APIKEY, HEADERS).subject_collection_items;
        const res = { class: CLASSES.map(([type_id, type_name]) => ({ type_id, type_name })), list: vods(items) };
        if (filter) res.filters = filters();
        return JSON.stringify(res);
    },

    category(tid, pg, filter, extend) {
        extend = extend || {};
        const page = '&start=' + (parseInt(pg) - 1) * 20 + '&count=20';
        let path, key = 'items';
        if (tid === 'hot_gaia') {
            path = '/movie/hot_gaia' + APIKEY + '&sort=' + (extend.sort || 'recommend') + '&area=' + encodeURIComponent(extend.area || '全部');
        } else if (COLLECTIONS[tid]) {
            const [fk, def] = COLLECTIONS[tid];
            path = '/subject_collection/' + (extend[fk] || def) + '/items' + APIKEY;
            key = 'subject_collection_items';
        } else { // movie / tv：除 sort 外的筛选值拼成 tags
            const tags = Object.keys(extend).filter(k => k !== 'sort' && extend[k]).map(k => extend[k]).join(',');
            path = '/' + (tid === 'tv' ? 'tv' : 'movie') + '/recommend' + APIKEY + '&sort=' + (extend.sort || 'T') + '&tags=' + encodeURIComponent(tags);
        }
        const data = getJson(API + path + page, HEADERS);
        return JSON.stringify({ list: vods(data[key]), page: parseInt(pg), pagecount: 9999, limit: 20, total: 999999 });
    },
};
