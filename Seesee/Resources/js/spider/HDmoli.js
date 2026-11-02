// 内置茉莉，对应 itv 单线路包 custom_spider_modified.jar 的 csp_HDmoli。
// 详情页 button.resource-option 的 data-url 为网盘分享链接，交给 pan/cloud.js 列目录。
import { load } from 'assets://js/lib/cat.js';
import { seedCreds, playFrom, playUrl, play } from './pan/cloud.js';

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36';
// 同单线路包 config.json 的 panOrder
const PAN_ORDER = ['pan.baidu.com', 'drive.uc.cn', 'pan.quark.cn', 'pan.xunlei.com', 'guangyapan.com', 'cloud.189.cn', '123pan|123684|123865|123912', 'aliyundrive.com|alipan.com', 'caiyun.139.com'];
let host = '';

const get = path => req(host + path, { headers: { 'User-Agent': UA }, timeout: 15000 }).content || '';
const panRank = u => { const i = PAN_ORDER.findIndex(p => p.split('|').some(x => u.includes(x))); return i < 0 ? 99 : i; };

// 首页 / 分类 / 搜索共用的列表解析；搜索结果的相对海报补全 host
function vods(html, sel) {
    const $ = load(html);
    return $(sel).toArray().map(e => {
        const a = $(e).find('a.myui-vodlist__thumb').first();
        let pic = $(e).find('img.vod-poster').first().attr('src') || '';
        if (pic && !pic.startsWith('http')) pic = host + pic;
        return { vod_id: a.attr('href') || '', vod_name: a.attr('title') || '', vod_pic: pic, vod_remarks: $(e).find('span.pic-text').text().trim() };
    }).filter(v => v.vod_id && v.vod_name);
}

const texts = ($, sel) => $(sel).toArray().map(e => $(e).text().trim()).filter(Boolean).join(' ');

function pickHost(sites) {
    const list = [].concat(sites || []).map(s => String(s).trim()).filter(Boolean);
    for (const u of list) {
        const code = req(u, { method: 'head', timeout: 5000 }).code;
        if (code >= 200 && code < 400) return u.replace(/\/$/, '');
    }
    return (list[0] || 'https://www.hdmoli.com').replace(/\/$/, '');
}

export default {
    // ext: {site: [...]}；网盘凭证同 Cloud.java
    init(ext) {
        const cfg = typeof ext === 'string' ? (ext.trim().startsWith('{') ? JSON.parse(ext) : {}) : (ext || {});
        host = pickHost(cfg.site);
        seedCreds(cfg);
    },

    home() {
        return JSON.stringify({ class: [['1', '电影'], ['2', '剧集'], ['41', '动画']].map(([type_id, type_name]) => ({ type_id, type_name })), filters: {} });
    },

    homeVod() { return JSON.stringify({ list: vods(get('/'), 'ul.myui-vodlist li') }); },

    category(tid, pg) {
        const list = vods(get(`/mlist/index${tid}-${pg}.html`), 'ul.myui-vodlist li');
        const page = parseInt(pg) || 1;
        return JSON.stringify({ list, page, pagecount: list.length ? page + 1 : page });
    },

    detail(id) {
        const $ = load(get(id));
        const links = [...new Set($('button.resource-option').toArray().map(e => $(e).attr('data-url') || ''))]
            .filter(u => /^https?:\/\//.test(u))
            .sort((a, b) => panRank(a) - panRank(b));
        const content = $('span#description-full').text() || $('p#movie-description').text();
        return JSON.stringify({
            list: [{
                vod_id: id, vod_name: $('h1.title').text().trim(),
                vod_pic: $('div.myui-content__thumb img.vod-poster').first().attr('src') || '',
                vod_remarks: $('div.myui-content__thumb span.pic-text').text().trim(),
                // jsoup Elements.text() 以空格连接多个元素
                vod_actor: texts($, 'p.data.actor-list a'), vod_director: texts($, 'p.data.actor-list + p.data a'),
                vod_content: content.replace(/\[.*?\]/g, '').replace(/ /g, '').trim(),
                vod_play_from: playFrom(links), vod_play_url: playUrl(links).replace(/\[\d{4,8}\]/g, ''),
            }],
        });
    },

    search(key) {
        if (!key) return JSON.stringify({ list: [] });
        return JSON.stringify({ list: vods(get('/search.php?searchkey=' + encodeURIComponent(key)), 'ul#searchList li') });
    },

    play(flag, id) { return play(flag, id); },
};
