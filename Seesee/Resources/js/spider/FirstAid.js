// 内置有来急救，对应 jar 的 csp_FirstAid（AndroidCatVodSpider/spider/FirstAid.java）。
// 分类 tid 为 "jijiu|<序号>"，同一页面按序号取不同板块；视频为直链 mp4（parse:0）。
import { load } from 'assets://js/lib/cat.js';

const HOST = 'https://m.youlai.cn';
const HEADERS = { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36' };
const NAMES = ['急救技能', '家庭生活', '急危重症', '常见损伤', '动物致伤', '海洋急救', '中毒急救', '意外事故'];

function doc(url) { return load(req(url, { headers: HEADERS, timeout: 15000 }).content || ''); }

function txt(el) { return el.text().replace(/\s+/g, ' ').trim(); }

function abs(u) { return u && u.startsWith('//') ? 'https:' + u : (u || ''); }

export default {
    init(ext) {},

    home(filter) {
        return JSON.stringify({ class: NAMES.map((n, i) => ({ type_id: 'jijiu|' + i, type_name: n })), list: [] });
    },

    homeVod() { return JSON.stringify({ list: [] }); },

    category(tid, pg, filter, extend) {
        const [cate, i] = tid.split('|'), idx = parseInt(i);
        const $ = doc(HOST + '/' + ((extend || {}).cateId || cate));
        const pic = abs($('.block100').eq(idx).attr('src'));
        const list = $('.jj-title-li').eq(idx).find('.list-br3').toArray().map(e => {
            const a = $(e).find('a').first();
            return { vod_id: HOST + (a.attr('href') || ''), vod_name: txt(a), vod_pic: pic };
        });
        return JSON.stringify({ list, page: 1, pagecount: 1, limit: list.length, total: list.length });
    },

    detail(id) {
        const $ = doc(id);
        const title = txt($('.video-title.h1-title'));
        const play = $('#video source').attr('src') || $('#video').attr('src') || '';
        return JSON.stringify({
            list: [{
                vod_id: id, vod_name: title, vod_pic: abs($('.video-cover.list-flex-in img').attr('src')),
                vod_actor: txt($('span.doc-name')), vod_area: '中国', vod_content: txt($('.img-text-con')),
                vod_play_from: 'Qile', vod_play_url: title + '$' + play,
            }],
        });
    },

    search(key, quick, pg) {
        const $ = doc(HOST + '/cse/search?q=' + encodeURIComponent(key));
        const list = $('.search-video-li.list-br2').toArray().map(e => {
            const li = $(e);
            return { vod_id: HOST + (li.find('a').attr('href') || ''), vod_name: txt(li.find('h5.line-clamp1')), vod_pic: abs(li.find('dt.logo-bg img').attr('src')) };
        });
        return JSON.stringify({ list, page: parseInt(pg || 1) });
    },

    play(flag, id, flags) {
        return JSON.stringify({ parse: 0, url: id, header: HEADERS });
    },
};
