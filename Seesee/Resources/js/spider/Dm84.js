// 内置动漫巴士，对应 jar 的 csp_Dm84（AndroidCatVodSpider/spider/Dm84.java）。
// 播放页 iframe 为站点播放器，交给 App 嗅探（parse:1）。
import { load } from 'assets://js/lib/cat.js';

const HOST = 'https://dm84.tv';
const HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
};
const BY = { '按时间': 'time', '按人气': 'hits', '按评分': 'score' };

function doc(path) { return load(req(HOST + path, { headers: HEADERS, timeout: 15000 }).content || ''); }

function txt(el) { return el.text().replace(/\s+/g, ' ').trim(); }

function vods($) {
    return $('div.item').toArray().map(e => {
        const it = $(e), a = it.find('a.title'), href = a.attr('href') || '';
        if (!href.startsWith('/v/')) return null;
        return { vod_id: href.split('/')[2], vod_name: txt(a), vod_pic: it.find('a.cover').attr('data-bg') || '', vod_remarks: txt(it.find('span.desc')) };
    }).filter(Boolean);
}

function filter(name, key, texts) {
    const value = texts.filter(Boolean).map(t => ({ n: t.replace('按', ''), v: key === 'by' ? (BY[t] || t) : (t === '全部' ? '' : t) }));
    return { key, name, value };
}

export default {
    init(ext) {},

    home(f) {
        const $ = doc('/');
        const classes = [], seen = new Set();
        $('ul.nav_row > li > a').each((_, e) => {
            const href = $(e).attr('href') || '';
            if (!href.startsWith('/list-')) return;
            const tid = href.split('-')[1].split('.')[0];
            if (seen.has(tid)) return;
            seen.add(tid);
            classes.push({ type_id: tid, type_name: txt($(e)).slice(0, 2) });
        });
        const filters = {};
        // ponytail: 每个分类一次请求，和原 Java 一致
        if (f) for (const c of classes) {
            const p = doc('/list-' + c.type_id + '.html'), divs = p('ul.list_filter > li > div').toArray();
            if (divs.length < 3) continue;
            const t = divs.slice(0, 3).map(d => p(d).find('a').toArray().map(a => txt(p(a))));
            filters[c.type_id] = [filter('类型', 'type', t[0]), filter('时间', 'year', t[1]), filter('排序', 'by', t[2])];
        }
        return JSON.stringify({ class: classes, filters, list: vods($) });
    },

    homeVod() { return JSON.stringify({ list: [] }); },

    category(tid, pg, filter, extend) {
        extend = extend || {};
        const path = '/show-' + tid + '--' + (extend.by || 'time') + '-' + encodeURIComponent(extend.type || '') + '--' + (extend.year || '') + '-' + pg + '.html';
        return JSON.stringify({ list: vods(doc(path)), page: parseInt(pg) });
    },

    detail(id) {
        const $ = doc('/v/' + id);
        const meta = (attr, v) => $('meta[' + attr + '="' + v + '"]').attr('content') || '';
        const lists = $('ul.play_list').toArray(), froms = [], urls = [];
        $('ul.tab_control > li').each((i, li) => {
            if (i >= lists.length) return;
            const eps = $(lists[i]).find('a').toArray().map(a => txt($(a)) + '$' + $(a).attr('href'));
            if (eps.length) { froms.push(txt($(li))); urls.push(eps.join('#')); }
        });
        return JSON.stringify({
            list: [{
                vod_id: id, vod_name: txt($('h1.v_title')), vod_pic: meta('property', 'og:image'),
                vod_remarks: txt($('p.v_desc > span.desc')), type_name: meta('name', 'og:video:class'),
                vod_year: meta('name', 'og:video:release_date'), vod_area: meta('name', 'og:video:area'),
                vod_actor: meta('name', 'og:video:actor'), vod_director: meta('name', 'og:video:director'),
                vod_content: meta('property', 'og:description'),
                vod_play_from: froms.join('$$$'), vod_play_url: urls.join('$$$'),
            }],
        });
    },

    search(key, quick, pg) {
        return JSON.stringify({ list: vods(doc('/s----------.html?wd=' + encodeURIComponent(key))), page: parseInt(pg || 1) });
    },

    play(flag, id, flags) {
        const src = doc(id)('iframe').attr('src') || '';
        return JSON.stringify({ parse: 1, url: src, header: HEADERS });
    },
};
