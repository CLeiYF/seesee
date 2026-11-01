// 内置在线之家，对应 jar 的 csp_Zxzj（AndroidCatVodSpider/spider/Zxzj.java）。
// 原 zxzj.shop 已失效，zxzjhd.com 301 到 zxzj.run。
// 播放：player_aaaa 直链 m3u8 直接播；player-v2 解密成功直接播；否则交给 App 嗅探（parse:1）。
import { load, Crypto } from 'assets://js/lib/cat.js';

const HOST = 'https://www.zxzj.run';
const HEADERS = {
    'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/100.0.4896.77 Mobile/15E148 Safari/604.1',
    'Referer': HOST + '/', 'sec-fetch-dest': 'iframe', 'sec-fetch-mode': 'navigate', 'sec-fetch-site': 'cross-site',
};
const VIDEO_HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Referer': HOST + '/',
};

function html(path) { return req(path.startsWith('http') ? path : HOST + path, { headers: HEADERS, timeout: 15000 }).content || ''; }

function txt(el) { return el.text().replace(/\s+/g, ' ').trim(); }

function reg(s, re) { const m = s.match(re); return m ? m[1].trim() : ''; }

function vods($) {
    return $('.stui-vodlist > li, .stui-vodlist__media > li').toArray().map(e => {
        const it = $(e), a = it.find('a.stui-vodlist__thumb'), href = a.attr('href') || '';
        if (!href) return null;
        return {
            vod_id: href, vod_name: txt(it.find('h4.title a, h3.title a').first()),
            vod_pic: a.attr('data-original') || it.find('img').attr('src') || '', vod_remarks: txt(a.find('span')),
        };
    }).filter(Boolean);
}

// Java decodeStr：去掉中间 7 个混淆字符
function decode(s) { const n = Math.floor((s.length - 7) / 2); return s.slice(0, n) + s.slice(n + 7); }

export default {
    init(ext) {},

    home(filter) {
        const $ = load(html('/'));
        const classes = $('.stui-header__menu > li > a').toArray().map(a => $(a))
            .filter(a => (a.attr('href') || '').startsWith('/vodtype/'))
            .map(a => ({ type_id: a.attr('href'), type_name: txt(a) }));
        return JSON.stringify({ class: classes, list: vods($) });
    },

    homeVod() { return JSON.stringify({ list: [] }); },

    // tid 形如 /vodtype/2.html -> /vodtype/2-<pg>.html
    category(tid, pg, filter, extend) {
        return JSON.stringify({ list: vods(load(html(tid.split('.')[0] + '-' + pg + '.html'))), page: parseInt(pg), pagecount: 9999, limit: 12, total: 999999 });
    },

    detail(id) {
        const $ = load(html(id));
        const heads = $('.stui-pannel__head h3.title').toArray().map(h => txt($(h)));
        const froms = [], urls = [];
        $('ul.stui-content__playlist').each((i, ul) => {
            const eps = $(ul).find('a').toArray().map(a => txt($(a)) + '$' + $(a).attr('href'));
            if (eps.length) { froms.push(heads[i] || '在线之家' + (i + 1)); urls.push(eps.join('#')); }
        });
        const ps = $('.stui-content__detail > p'), info = txt(ps.eq(0));
        return JSON.stringify({
            list: [{
                vod_id: id, vod_name: txt($('.stui-content__detail > h1')),
                vod_pic: $('div.stui-content__thumb img').attr('data-original') || '',
                type_name: reg(info, /类型：([^/]+)/), vod_area: reg(info, /地区：([^/]+)/), vod_year: reg(info, /年份：(\d+)/),
                vod_actor: txt(ps.eq(1)), vod_director: txt(ps.eq(2)), vod_content: txt($('.detail-sketch')),
                vod_play_from: froms.join('$$$'), vod_play_url: urls.join('$$$'),
            }],
        });
    },

    search(key, quick, pg) {
        const h = html('/vodsearch/-------------.html?wd=' + encodeURIComponent(key) + '&submit=');
        if (h.includes('Just a moment')) return JSON.stringify({ list: [] }); // 站点开启人机验证
        return JSON.stringify({ list: vods(load(h)), page: parseInt(pg || 1) });
    },

    play(flag, id, flags) {
        const m = html(id).match(/player_aaaa=(.*?)<\/script>/);
        let url = '';
        try { url = m ? JSON.parse(m[1]).url || '' : ''; } catch (e) { /* 交给嗅探 */ }
        if (!url.startsWith('http')) return JSON.stringify({ parse: 1, url: HOST + id, header: HEADERS });
        if (url.includes('m3u8')) return JSON.stringify({ parse: 0, url, header: VIDEO_HEADERS });
        try {
            // player-v2：result_v2.data 反转后 hex 解码，再去混淆
            const data = JSON.parse(html(url).match(/result_v2 =(.*?);/)[1]).data;
            const real = decode(Crypto.enc.Hex.parse(data.split('').reverse().join('')).toString(Crypto.enc.Utf8));
            if (real.startsWith('http')) return JSON.stringify({ parse: 0, url: real, header: VIDEO_HEADERS });
        } catch (e) { /* 接口异常/网盘链接 */ }
        return JSON.stringify({ parse: 1, url, header: HEADERS });
    },
};
