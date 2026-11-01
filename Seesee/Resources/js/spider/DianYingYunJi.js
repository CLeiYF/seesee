// 内置电影云集，对应 jar 的 csp_DianYingYunJi（AndroidCatVodSpider/spider/DianYingYunJi.java）。
// WordPress 站，详情页里带夸克/百度等分享链接，交给 pan/cloud.js 列目录。
import { load } from 'assets://js/lib/cat.js';
import { seedCreds, playFrom, playUrl, play, isShare } from './pan/cloud.js';

const HOST = 'https://dyyjpro.com';
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

const get = url => req(url, { headers: { 'User-Agent': UA }, timeout: 15000 }).content || '';
const pick = (re, s) => (re.exec(s) || [])[1]?.trim() || '';

function vods($) {
    return $('article.post-item').toArray().map(e => {
        const a = $(e).find('h2.entry-title > a');
        let pic = $(e).find('div.entry-media > a').attr('data-bg') || '';
        if (pic && !pic.startsWith('http')) pic = HOST + pic;
        return { vod_id: a.attr('href'), vod_name: a.text().trim(), vod_pic: pic, vod_remarks: $(e).find('.entry-cat-dot').text().trim() };
    }).filter(v => v.vod_id);
}

export default {
    // 同 Cloud.java：ext 可带 { cookie, uccookie, tianyicookie, token }
    init(ext) { seedCreds(ext); },
    home() {
        const $ = load(get(HOST));
        const seen = new Set();
        const classes = $('#header-navbar > li.menu-item > a').toArray()
            .map(e => ({ type_id: $(e).attr('href') || '', type_name: $(e).text().trim() }))
            .filter(c => c.type_id.startsWith(HOST + '/category/') && !seen.has(c.type_id) && seen.add(c.type_id));
        return JSON.stringify({ class: classes, list: vods($) });
    },
    homeVod() { return JSON.stringify({ list: vods(load(get(HOST))) }); },
    category(tid, pg) {
        const page = Number(pg) || 1;
        const list = vods(load(get(`${tid}/page/${page}`)));
        return JSON.stringify({ page, pagecount: list.length ? page + 1 : page, limit: 19, total: (page + 1) * 19, list });
    },
    detail(id) {
        const $ = load(get(id));
        const text = $('article.post-content > p').text();
        const links = [...new Set($('article.post-content p a').toArray().map(a => ($(a).attr('href') || '').trim()).filter(isShare))];
        return JSON.stringify({ list: [{
            vod_id: id,
            vod_name: $('h1.post-title').first().text().trim(),
            vod_pic: $('article.post-content img').first().attr('src') || '',
            type_name: $('span.meta-cat-dot').first().text().trim(),
            vod_director: pick(/导演:(.*?)编剧:/, text),
            vod_area: pick(/地区:(.*?)语言:/, text),
            vod_actor: pick(/主演:(.*?)类型:/, text),
            vod_year: pick(/上映日期:(.*?)片长:/, text),
            vod_content: pick(/剧情简介(.*?)获奖情况/, text) || $('article.post-content > p').eq(1).text().trim(),
            vod_play_from: playFrom(links),
            vod_play_url: playUrl(links),
        }] });
    },
    search(key, quick, pg) {
        const page = Number(pg) || 1;
        const url = `${HOST}/${page > 1 ? `page/${page}/` : ''}?s=${encodeURIComponent(key)}`;
        return JSON.stringify({ page, list: vods(load(get(url))) });
    },
    play(flag, id) { return play(flag, id); },
};
