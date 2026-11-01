// 内置动漫MIKU，对应 jar 的 csp_Ysj（AndroidCatVodSpider/spider/Ysj.java）。
// 站点自研播放器（url 为 Tuzimi-xxx 形式），和原 Java 一样交给 App 嗅探播放页（parse:1）。
import { load } from 'assets://js/lib/cat.js';

const HOST = 'https://www.dmmiku.com';
const PLAY = '/index.php/vod/play/id/';
const HEADERS = { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36' };

function html(path) { return req(HOST + path, { headers: HEADERS, timeout: 15000 }).content || ''; }

function txt(el) { return el.text().replace(/\s+/g, ' ').trim(); }

function vods($, sel) {
    return $(sel).toArray().map(e => {
        const it = $(e), a = it.find('a').first(), parts = (a.attr('href') || '').split('/');
        if (parts.length < 6) return null;
        return { vod_id: parts[5], vod_name: a.attr('title') || '', vod_pic: HOST + (a.attr('data-original') || ''), vod_remarks: txt(it.find('span.pic_text')) };
    }).filter(Boolean);
}

function filter(name, key, texts) {
    return { key, name, value: texts.filter(Boolean).map(t => ({ n: t, v: t.replace('全部', '') })) };
}

export default {
    init(ext) {},

    home(f) {
        const $ = load(html('/index.php/vod/show/id/20.html'));
        const texts = i => $('div#hl0' + i + ' a').toArray().map(a => txt($(a)));
        const array = [filter('地區', 'area', texts(3)), filter('年份', 'year', texts(4)), filter('語言', 'lang', texts(5)), filter('字母', 'letter', texts(6))];
        const classes = [], filters = {};
        $('div#hl02 a').each((_, a) => {
            let tid = ($(a).attr('href') || '').split('/')[5] || '';
            if (tid.includes('.html')) tid = '';
            classes.push({ type_id: tid, type_name: txt($(a)).replace('BD', '') });
            filters[tid] = array;
        });
        return JSON.stringify({ class: classes, filters, list: vods($, 'li.vodlist_item') });
    },

    homeVod() { return JSON.stringify({ list: [] }); },

    category(tid, pg, filter, extend) {
        const e = extend || {};
        let path = '/index.php/vod/show';
        if (e.area) path += '/area/' + encodeURIComponent(e.area);
        if (tid) path += '/class/' + tid;
        path += '/id/20';
        for (const k of ['lang', 'letter', 'year']) if (e[k]) path += '/' + k + '/' + encodeURIComponent(e[k]);
        if (String(pg) !== '1') path += '/page/' + pg;
        return JSON.stringify({ list: vods(load(html(path + '.html')), 'li.vodlist_item'), page: parseInt(pg) });
    },

    detail(id) {
        const $ = load(html('/index.php/vod/detail/id/' + id));
        const data = $('li.data').toArray();
        const tags = (data.length ? $(data[0]).find('a').toArray().map(a => txt($(a))) : []).concat(['', '', '']);
        const lists = $('ul.content_playlist').toArray(), froms = [], urls = [];
        $('div.play_source_tab > a').each((i, src) => {
            if (i >= lists.length) return;
            const eps = $(lists[i]).find('a').toArray().map(a => txt($(a)) + '$' + ($(a).attr('href') || '').replace(PLAY, ''));
            if (eps.length) { froms.push($(src).attr('alt') || txt($(src))); urls.push(eps.join('#')); }
        });
        return JSON.stringify({
            list: [{
                vod_id: id, vod_name: txt($('h2.title')), vod_pic: HOST + ($('a.vodlist_thumb').attr('data-original') || ''),
                vod_year: tags[0], vod_area: tags[1], type_name: tags[2],
                vod_actor: data.length > 2 ? txt($(data[2])).replace('主演：', '') : '',
                vod_director: data.length > 3 ? txt($(data[3])).replace('导演：', '') : '',
                vod_content: txt($('div.content_desc > span')),
                vod_play_from: froms.join('$$$'), vod_play_url: urls.join('$$$'),
            }],
        });
    },

    search(key, quick, pg) {
        const h = html('/index.php/vod/search.html?wd=' + encodeURIComponent(key) + '&submit=');
        const list = h.includes('很抱歉，暂无相关视频') ? [] : vods(load(h), 'li.searchlist_item');
        return JSON.stringify({ list, page: parseInt(pg || 1) });
    },

    play(flag, id, flags) {
        return JSON.stringify({ parse: 1, url: HOST + PLAY + id, header: HEADERS });
    },
};
