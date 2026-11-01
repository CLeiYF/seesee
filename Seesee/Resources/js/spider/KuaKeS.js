// 内置酷客网盘社，对应 jar 的 csp_KuaKeS（AndroidCatVodSpider/spider/KuaKeS.java）。
// 详情页的分享链接要调 admin-ajax（wb_mpdl_front）换取，再交给 pan/cloud.js 列目录。
import { load } from 'assets://js/lib/cat.js';
import { seedCreds, playFrom, playUrl, play } from './pan/cloud.js';

const HOST = 'https://kuakes.com';
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

const get = (url, cookie) => req(url, { headers: { 'User-Agent': UA, ...(cookie ? { cookie } : {}) }, timeout: 15000 }).content || '';
const pick = (re, s) => (re.exec(s) || [])[1]?.trim() || '';

function vods($) {
    return $('div.articles-list article.post').toArray().map(e => {
        const a = $(e).find('a.post-title');
        let pic = $(e).find('img').attr('data-lazy-src') || '';
        if (pic && !pic.startsWith('http')) pic = HOST + pic;
        return { vod_id: a.attr('href'), vod_name: a.text().trim(), vod_pic: pic, vod_remarks: $(e).find('span.db_score').text().trim() };
    }).filter(v => v.vod_id);
}

export default {
    // 同 Cloud.java：ext 可带 { cookie, uccookie, tianyicookie, token }
    init(ext) { seedCreds(ext); },
    home() {
        const $ = load(get(HOST));
        const classes = $('#J_topNav a').toArray()
            .map(e => ({ type_id: $(e).attr('href') || '', type_name: $(e).text().trim() }))
            .filter(c => c.type_id.startsWith(HOST) && !c.type_id.includes('/news') && !c.type_id.includes('/novel'));
        return JSON.stringify({ class: classes, list: vods($) });
    },
    homeVod() { return JSON.stringify({ list: vods(load(get(HOST))) }); },
    category(tid, pg) {
        const page = Number(pg) || 1;
        const base = tid.split('?')[0].replace(/\/$/, ''), query = tid.includes('?') ? '?' + tid.split('?')[1] : '';
        const list = vods(load(get(`${base}/page/${page}${query}`)));
        return JSON.stringify({ page, pagecount: list.length ? page + 1 : page, limit: 19, total: (page + 1) * 19, list });
    },
    detail(id) {
        const $ = load(get(id));
        const text = $('div.wp-block-media-text__content > p').text();
        const a = $('div.magicpost-cont-bd > a').first();
        const links = [];
        if (a.attr('data-rid')) {
            const r = req(HOST + '/wp-admin/admin-ajax.php', { method: 'post', postType: 'form', timeout: 15000,
                headers: { 'User-Agent': UA, Referer: id },
                data: { action: 'wb_mpdl_front', rid: a.attr('data-rid'), pid: a.attr('data-pid') } });
            try {
                const d = JSON.parse(r.content).data || {};
                if (d.url) links.push(d.pwd && !/[?&]pwd=/.test(d.url) ? `${d.url}?pwd=${d.pwd}` : d.url);
            } catch { /* 没有链接 */ }
        }
        return JSON.stringify({ list: [{
            vod_id: id,
            vod_name: $('h1.title-detail').first().text().trim(),
            vod_pic: $('div.media-pic img').first().attr('data-lazy-src') || '',
            vod_director: pick(/导演:(.*?)编剧:/, text),
            vod_area: pick(/地区:(.*?)语言:/, text),
            vod_actor: pick(/主演:(.*?)类型:/, text),
            vod_year: pick(/上映日期:(.*?)\(/, text),
            type_name: pick(/类型:(.*?)制片/, text),
            vod_content: $('div.article-detail > p').text().trim(),
            vod_play_from: playFrom(links),
            vod_play_url: playUrl(links),
        }] });
    },
    search(key, quick, pg) {
        const page = Number(pg) || 1;
        const url = `${HOST}/${page > 1 ? `page/${page}/` : ''}?s=${encodeURIComponent(key)}`;
        return JSON.stringify({ page, list: vods(load(get(url, 'esc_search_captcha=1; result=43'))) });
    },
    play(flag, id) { return play(flag, id); },
};
