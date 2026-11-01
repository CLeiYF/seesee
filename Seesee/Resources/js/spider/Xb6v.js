// 内置新版 6v 电影，对应 jar 的 csp_Xb6v（AndroidCatVodSpider/spider/Xb6v.java）。
// 线路：磁力、站内在线播放（播放页里找直链 / iframe 里的 m3u8）、网盘分享（pan/cloud.js 列目录）。
import { load } from 'assets://js/lib/cat.js';
import { seedCreds, playFrom, playUrl, play as panPlay, isShare, clientFor } from './pan/cloud.js';

const HOST = 'https://www.xb6v.com';
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
// 同 Util.RULE
const MEDIA = /http((?!http).){12,}?\.(m3u8|mp4|mkv|flv|mp3|m4a|aac)\?[^"'\s<]*|http((?!http).){12,}?\.(m3u8|mp4|mkv|flv|mp3|m4a|aac)|http((?!http).)*?video\/tos[^"'\s<]*/;

const get = url => req(url, { headers: { 'User-Agent': UA, Referer: HOST + '/' }, timeout: 15000 }).content || '';
const pick = (re, s) => (re.exec(s) || [])[1]?.trim() || '';
const clean = s => s.replace(/<br\s*\/?>/g, '').replace(/&nbsp;/g, '').replace(/&amp;/g, '').replace(/middot;/g, '・')
    .replace(/　{4,}\s?　?/g, ',').replace(/　/g, '');
const strip = s => s.replace(/<\/?[^>]+>/g, '').replace(/\n/g, '').replace(/&amp;/g, '').replace(/middot;/g, '・')
    .replace(/ldquo;/g, '【').replace(/rdquo;/g, '】').replace(/　/g, '').trim();
const ep = (name, url) => `${String(name).replace(/[#$]/g, ' ').trim() || '播放'}$${url}`;
let searchIds = {};   // 关键词 -> 搜索结果路径（翻页用）

function vods($) {
    return $('#post_container .post_hover').toArray().map(item => {
        const a = $(item).find('a.zoom').first();
        return { vod_id: a.attr('href'), vod_name: (a.attr('title') || '').replace(/<\/?[^>]+>/g, ''),
            vod_pic: a.find('img').attr('src') || '', vod_remarks: $(item).find('[rel="category tag"]').text().trim() };
    }).filter(v => v.vod_id);
}

export default {
    // 同 Cloud.java：ext 可带 { cookie, uccookie, tianyicookie, token }
    init(ext) { searchIds = {}; seedCreds(ext); },
    home() {
        const $ = load(get(HOST));
        const classes = [], filters = {};
        const items = $('#menus > li > a').toArray();
        items.forEach((e, i) => {
            if (i < 2 || i === items.length - 1) return;
            const typeId = $(e).attr('href'), typeName = $(e).text().trim();
            if (!typeId || !typeId.startsWith('/')) return;
            const subs = $(e).next('ul').find('a').toArray();
            if (subs.length) {
                filters[typeId] = [{ key: 'cateId', name: '类型', value: [{ n: '不限', v: '' },
                    ...subs.map(a => ({ n: $(a).text().trim(), v: ($(a).attr('href') || '').replace(typeId, '') }))] }];
            }
            classes.push({ type_id: typeId, type_name: typeName });
        });
        return JSON.stringify({ class: classes, filters, list: vods($) });
    },
    homeVod() { return JSON.stringify({ list: vods(load(get(HOST))) }); },
    category(tid, pg, filter, extend) {
        const page = Number(pg) || 1;
        let url = HOST + tid + ((extend && extend.cateId) || '');
        if (page > 1) url += `index_${page}.html`;
        const $ = load(get(url));
        const last = $('.pagination > a').last().attr('href') || '';
        const count = Number(pick(/index_(\d+)\.html/, last)) || page;
        const list = vods($);
        return JSON.stringify({ page, pagecount: Math.max(count, page), limit: 18,
            total: page >= count ? (page - 1) * 18 + list.length : count * 18, list });
    },
    detail(id) {
        const html = get(HOST + id);
        const $ = load(html);
        const from = [], urls = [];
        const magnets = $('#post_content table a').toArray().map(a => ep($(a).text(), $(a).attr('href') || ''))
            .filter(s => /\$(magnet|thunder|ed2k):/.test(s));
        if (magnets.length) { from.push('磁力线路'); urls.push(magnets.join('#')); }
        const shares = [];
        $('div.context div.box').each((_, box) => {
            const eps = [];
            $(box).find('a').each((__, a) => {
                const href = ($(a).attr('href') || '').trim();
                if (!href) return;
                if (isShare(href)) shares.push(href);
                else if (href.startsWith('/e/DownSys/play/')) eps.push(ep($(a).text(), href));
            });
            if (eps.length) { from.push($(box).find('h3').text().trim() || '在线播放'); urls.push(eps.join('#')); }
        });
        const pf = playFrom(shares), pu = playUrl(shares);
        if (pf) { from.push(pf); urls.push(pu); }
        const part = $('.context').html() || '';
        const or = (...vals) => vals.find(Boolean) || '';
        return JSON.stringify({ list: [{
            vod_id: id,
            vod_name: $('.article_container > h1').text().trim(),
            vod_pic: $('#post_content img').first().attr('src') || '',
            type_name: or(pick(/◎类　　别　(.*?)<br/, part), $('[rel="category tag"]').first().text().trim()),
            vod_year: or(pick(/◎年　　代　(.*?)<br/, part), pick(/首播:(.*?)<br/, part)),
            vod_area: or(pick(/◎产　　地　(.*?)<br/, part), pick(/地区:(.*?)<br/, part)),
            vod_remarks: pick(/◎上映日期　(.*?)<br/, part),
            vod_actor: clean(or(pick(/◎演　　员　(.*?)<\/p>/, part), pick(/◎主　　演　(.*?)<\/p>/, part), pick(/主演:(.*?)<br/, part))),
            vod_director: clean(or(pick(/◎导　　演　(.*?)<br/, part), pick(/导演:(.*?)<br/, part))),
            vod_content: strip(or(pick(/◎简　　介([\s\S]*?)<hr/i, part), pick(/简介([\s\S]*?)<\/p>/i, part))),
            vod_play_from: from.join('$$$'),
            vod_play_url: urls.join('$$$'),
        }] });
    },
    search(key, quick, pg) {
        const page = Number(pg) || 1;
        let path = searchIds[key];
        if (!path) {
            const r = req(HOST + '/e/search/so.php', { method: 'post', redirect: 0, timeout: 15000,
                headers: { 'User-Agent': UA, Origin: HOST, Referer: HOST + '/', 'Content-Type': 'application/x-www-form-urlencoded' },
                body: `show=title&tempid=1&tbname=article&mid=1&dopost=search&submit=&keyboard=${encodeURIComponent(key)}` });
            const loc = Object.entries(r.headers || {}).find(([k]) => k.toLowerCase() === 'location')?.[1] || '';
            const sid = pick(/searchid=(\d+)/, loc);
            if (!sid) return JSON.stringify({ list: [] });
            path = searchIds[key] = `/e/search/result/?searchid=${sid}`;
        }
        // 结果页翻页参数 page 从 0 开始
        const url = HOST + path + (page > 1 ? `&page=${page - 1}` : '');
        return JSON.stringify({ page, list: vods(load(get(url))) });
    },
    play(flag, id) {
        if (/^(magnet|thunder|ed2k):/.test(id)) return JSON.stringify({ parse: 0, url: id });
        if (clientFor({ flag })) return panPlay(flag, id);
        let html = get(HOST + id);
        let m = MEDIA.exec(html);
        if (!m) {
            const iframe = load(html)('iframe').attr('src');
            if (iframe) m = MEDIA.exec(get(joinUrl(HOST + id, iframe)));
        }
        return JSON.stringify(m ? { parse: 0, url: m[0], header: { 'User-Agent': UA } } : { parse: 1, url: HOST + id });
    },
};
