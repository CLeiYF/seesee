// 内置网盘分享站，对应 itv 单线路包 custom_spider_modified.jar 的 csp_PanWebShare（快映/木偶/闪电/蜡笔/八零 共用）。
// MacCMS 网盘模板站：详情页 .module-row-text 的 data-clipboard-text 为分享链接，交给 pan/cloud.js 列目录。
// 花卷（csp_PanWebShareHJ）只是选择器不同，见 PanWebShareHJ.js，通过 make() 复用。
import { load } from 'assets://js/lib/cat.js';
import { seedCreds, playFrom, playUrl, play, isShare } from './pan/cloud.js';

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36';
// 同 Java homeContent 写死的筛选（两个类共用）
const FILTERS = {"1":[{"key":"cateId","name":"类型","value":[{"n":"全部","v":"1"},{"n":"科幻片","v":"6"},{"n":"爱情片","v":"7"},{"n":"战争片","v":"8"},{"n":"恐怖片","v":"9"},{"n":"高码片","v":"10"},{"n":"动画片","v":"11"},{"n":"动作片","v":"12"}]},{"key":"class","name":"剧情","value":[{"n":"全部","v":""},{"n":"喜剧","v":"喜剧"},{"n":"爱情","v":"爱情"},{"n":"恐怖","v":"恐怖"},{"n":"动作","v":"动作"},{"n":"科幻","v":"科幻"},{"n":"剧情","v":"剧情"},{"n":"战争","v":"战争"},{"n":"警匪","v":"警匪"},{"n":"犯罪","v":"犯罪"},{"n":"动画","v":"动画"},{"n":"奇幻","v":"奇幻"},{"n":"武侠","v":"武侠"},{"n":"冒险","v":"冒险"},{"n":"枪战","v":"枪战"},{"n":"悬疑","v":"悬疑"},{"n":"惊悚","v":"惊悚"},{"n":"经典","v":"经典"}]},{"key":"area","name":"地区","value":[{"n":"全部","v":""},{"n":"大陆","v":"大陆"},{"n":"香港","v":"香港"},{"n":"台湾","v":"台湾"},{"n":"美国","v":"美国"},{"n":"法国","v":"法国"},{"n":"英国","v":"英国"},{"n":"日本","v":"日本"},{"n":"韩国","v":"韩国"},{"n":"德国","v":"德国"},{"n":"泰国","v":"泰国"},{"n":"印度","v":"印度"},{"n":"意大利","v":"意大利"},{"n":"西班牙","v":"西班牙"},{"n":"加拿大","v":"加拿大"},{"n":"其他","v":"其他"}]},{"key":"year","name":"年份","value":[{"n":"全部","v":""},{"n":"2026","v":"2026"},{"n":"2025","v":"2025"},{"n":"2024","v":"2024"},{"n":"2023","v":"2023"},{"n":"2022","v":"2022"},{"n":"2021","v":"2021"},{"n":"2020","v":"2020"},{"n":"2019","v":"2019"},{"n":"2018","v":"2018"},{"n":"2017","v":"2017"},{"n":"2016","v":"2016"},{"n":"2015","v":"2015"},{"n":"2014","v":"2014"},{"n":"2013","v":"2013"},{"n":"2012","v":"2012"},{"n":"2011","v":"2011"},{"n":"2010","v":"2010"}]},{"key":"by","name":"排序","value":[{"n":"时间","v":"time"},{"n":"人气","v":"hits"},{"n":"评分","v":"score"}]}],"2":[{"key":"cateId","name":"类型","value":[{"n":"全部","v":"2"},{"n":"国产剧","v":"13"},{"n":"日韩剧","v":"14"},{"n":"欧美剧","v":"15"},{"n":"港台剧","v":"16"}]},{"key":"class","name":"剧情","value":[{"n":"全部","v":""},{"n":"古装","v":"古装"},{"n":"战争","v":"战争"},{"n":"青春偶像","v":"青春偶像"},{"n":"喜剧","v":"喜剧"},{"n":"家庭","v":"家庭"},{"n":"犯罪","v":"犯罪"},{"n":"动作","v":"动作"},{"n":"奇幻","v":"奇幻"},{"n":"剧情","v":"剧情"},{"n":"历史","v":"历史"},{"n":"经典","v":"经典"},{"n":"乡村","v":"乡村"},{"n":"情景","v":"情景"},{"n":"商战","v":"商战"},{"n":"网剧","v":"网剧"},{"n":"其他","v":"其他"}]},{"key":"area","name":"地区","value":[{"n":"全部","v":""},{"n":"大陆","v":"大陆"},{"n":"香港","v":"香港"},{"n":"台湾","v":"台湾"},{"n":"美国","v":"美国"},{"n":"日本","v":"日本"},{"n":"韩国","v":"韩国"},{"n":"泰国","v":"泰国"},{"n":"英国","v":"英国"},{"n":"新加坡","v":"新加坡"},{"n":"其他","v":"其他"}]},{"key":"year","name":"年份","value":[{"n":"全部","v":""},{"n":"2026","v":"2026"},{"n":"2025","v":"2025"},{"n":"2024","v":"2024"},{"n":"2023","v":"2023"},{"n":"2022","v":"2022"},{"n":"2021","v":"2021"},{"n":"2020","v":"2020"},{"n":"2019","v":"2019"},{"n":"2018","v":"2018"},{"n":"2017","v":"2017"},{"n":"2016","v":"2016"},{"n":"2015","v":"2015"},{"n":"2014","v":"2014"},{"n":"2013","v":"2013"},{"n":"2012","v":"2012"},{"n":"2011","v":"2011"},{"n":"2010","v":"2010"}]},{"key":"by","name":"排序","value":[{"n":"时间","v":"time"},{"n":"人气","v":"hits"},{"n":"评分","v":"score"}]}],"3":[{"key":"cateId","name":"类型","value":[{"n":"全部","v":"3"},{"n":"日韩","v":"22"},{"n":"国产","v":"20"},{"n":"欧美","v":"21"}]},{"key":"year","name":"年份","value":[{"n":"全部","v":""},{"n":"2026","v":"2026"},{"n":"2025","v":"2025"},{"n":"2024","v":"2024"},{"n":"2023","v":"2023"},{"n":"2022","v":"2022"},{"n":"2021","v":"2021"},{"n":"2020","v":"2020"},{"n":"2019","v":"2019"},{"n":"2018","v":"2018"},{"n":"2017","v":"2017"},{"n":"2016","v":"2016"},{"n":"2015","v":"2015"},{"n":"2014","v":"2014"},{"n":"2013","v":"2013"},{"n":"2012","v":"2012"},{"n":"2011","v":"2011"},{"n":"2010","v":"2010"},{"n":"2009","v":"2009"},{"n":"2008","v":"2008"},{"n":"2007","v":"2007"},{"n":"2006","v":"2006"},{"n":"2005","v":"2005"},{"n":"2004","v":"2004"}]},{"key":"by","name":"排序","value":[{"n":"时间","v":"time"},{"n":"人气","v":"hits"},{"n":"评分","v":"score"}]}],"4":[{"key":"area","name":"地区","value":[{"n":"全部","v":""},{"n":"大陆","v":"大陆"},{"n":"日本","v":"日本"},{"n":"欧美","v":"欧美"},{"n":"其他","v":"其他"}]},{"key":"year","name":"年份","value":[{"n":"全部","v":""},{"n":"2026","v":"2026"},{"n":"2025","v":"2025"},{"n":"2024","v":"2024"},{"n":"2023","v":"2023"},{"n":"2022","v":"2022"},{"n":"2021","v":"2021"},{"n":"2020","v":"2020"},{"n":"2019","v":"2019"},{"n":"2018","v":"2018"},{"n":"2017","v":"2017"},{"n":"2016","v":"2016"},{"n":"2015","v":"2015"},{"n":"2014","v":"2014"},{"n":"2013","v":"2013"},{"n":"2012","v":"2012"},{"n":"2011","v":"2011"},{"n":"2010","v":"2010"},{"n":"2009","v":"2009"},{"n":"2008","v":"2008"},{"n":"2007","v":"2007"},{"n":"2006","v":"2006"},{"n":"2005","v":"2005"},{"n":"2004","v":"2004"}]},{"key":"by","name":"排序","value":[{"n":"时间","v":"time"},{"n":"人气","v":"hits"},{"n":"评分","v":"score"}]}],"5":[{"key":"year","name":"年份","value":[{"n":"全部","v":""},{"n":"2026","v":"2026"},{"n":"2025","v":"2025"},{"n":"2024","v":"2024"},{"n":"2023","v":"2023"},{"n":"2022","v":"2022"},{"n":"2021","v":"2021"},{"n":"2020","v":"2020"},{"n":"2019","v":"2019"},{"n":"2018","v":"2018"},{"n":"2017","v":"2017"},{"n":"2016","v":"2016"},{"n":"2015","v":"2015"},{"n":"2014","v":"2014"},{"n":"2013","v":"2013"},{"n":"2012","v":"2012"},{"n":"2011","v":"2011"},{"n":"2010","v":"2010"}]},{"key":"by","name":"排序","value":[{"n":"时间","v":"time"},{"n":"人气","v":"hits"},{"n":"评分","v":"score"}]}],"26":[{"key":"cateId","name":"类型","value":[{"n":"全部","v":"26"},{"n":"高分电影","v":"29"},{"n":"高分剧集","v":"27"},{"n":"高分外剧","v":"30"},{"n":"国漫之光","v":"28"}]},{"key":"year","name":"年份","value":[{"n":"全部","v":""},{"n":"2026","v":"2026"},{"n":"2025","v":"2025"},{"n":"2024","v":"2024"},{"n":"2023","v":"2023"},{"n":"2022","v":"2022"},{"n":"2021","v":"2021"},{"n":"2020","v":"2020"},{"n":"2019","v":"2019"},{"n":"2018","v":"2018"},{"n":"2017","v":"2017"},{"n":"2016","v":"2016"},{"n":"2015","v":"2015"},{"n":"2014","v":"2014"},{"n":"2013","v":"2013"},{"n":"2012","v":"2012"},{"n":"2011","v":"2011"},{"n":"2010","v":"2010"},{"n":"2009","v":"2009"},{"n":"2008","v":"2008"},{"n":"2007","v":"2007"},{"n":"2006","v":"2006"},{"n":"2005","v":"2005"},{"n":"2004","v":"2004"}]},{"key":"by","name":"排序","value":[{"n":"时间","v":"time"},{"n":"人气","v":"hits"},{"n":"评分","v":"score"}]}]};
// 同单线路包 config.json 的 panOrder
const PAN_ORDER = ['pan.baidu.com', 'drive.uc.cn', 'pan.quark.cn', 'pan.xunlei.com', 'guangyapan.com', 'cloud.189.cn', '123pan|123684|123865|123912', 'aliyundrive.com|alipan.com', 'caiyun.139.com'];
const panRank = u => { const i = PAN_ORDER.findIndex(p => p.split('|').some(x => u.includes(x))); return i < 0 ? 99 : i; };

// 豆瓣图片要带 Referer 才能加载（同 Java d() 的 @Headers= 后缀）
export function pic(src) {
    const i = (src || '').lastIndexOf('http');
    const u = i >= 0 ? src.slice(i) : (src || '');
    return u.includes('douban') ? u + '@Headers=' + JSON.stringify({ 'User-Agent': UA, Referer: 'https://www.douban.com' }) : u;
}

function pickHost(sites) {
    const list = [].concat(sites || []).map(s => String(s).trim()).filter(Boolean);
    for (const u of list) {
        const code = req(u, { method: 'head', timeout: 5000 }).code;
        if (code >= 200 && code < 400) return u.replace(/\/$/, '');
    }
    return (list[0] || '').replace(/\/$/, '');
}

const joinText = ($, els) => els.toArray().map(a => $(a).text().trim()).join(',');

// 默认选择器即 PanWebShare.java；HJ 传入覆盖项
const BASE = {
    // 首页分类：span.module-tab-item 的 data-id / data-name
    classes: $ => $('span.module-tab-item.tab-item').toArray().map(e => [$(e).attr('data-id'), $(e).attr('data-name')]),
    // 详情页分享链接
    links: $ => $('.module-row-text').toArray().map(e => $(e).attr('data-clipboard-text') || ''),
    homeItems: '.module-item',
    item: ($, e) => {
        const a = $(e).find('.module-item-titlebox > a');
        return { vod_id: a.attr('href'), vod_name: a.attr('title') || '', vod_pic: pic($(e).find('.module-item-pic img').attr('data-src')), vod_remarks: $(e).find('.module-item-text').text().trim() };
    },
    searchItems: '.module-search-item',
    searchItem: ($, e) => {
        const a = $(e).find('.video-info-header a').first();
        return { vod_id: a.attr('href'), vod_name: a.attr('title') || '', vod_pic: pic($(e).find('.module-item-pic img').attr('data-src')),
            vod_remarks: $(e).find('.video-info-header a.video-serial').first().text().trim() };
    },
    // 同 Java h()：.video-info-item 中首个子元素含 label 的那行，取其中 a 的文字
    info: ($, label) => {
        const row = $('.video-info-item').toArray().find(e => $(e).children().first().text().includes(label));
        return row ? joinText($, $(row).find('a')) : '';
    },
    vod: ($, info) => ({
        vod_name: $('.video-info-header > .page-title').first().text().trim(),
        vod_pic: pic($('.module-item-pic img').first().attr('data-src')),
        vod_area: $('.video-info-header a.tag-link').last().text().trim(),
        type_name: joinText($, $('.video-info-header div.tag-link a')),
        vod_year: info('年代'), vod_director: info('导演'), vod_actor: info('主演'), vod_remarks: info('备注'),
        vod_content: $('p.sqjj_a').text(),
    }),
};

export function make(opts = {}) {
    const o = { ...BASE, ...opts };
    let host = '';
    const get = path => req(path.startsWith('http') ? path : host + path, { headers: { 'User-Agent': UA, Referer: host + '/' }, timeout: 15000 }).content || '';
    const vods = ($, sel, fn) => $(sel).toArray().map(e => fn($, e)).filter(v => v.vod_id && v.vod_name !== '臻彩');

    return {
        // ext: {site: [...]}；HEAD 探测第一个 2xx/3xx 的站点；网盘凭证同 Cloud.java
        init(ext) {
            const cfg = typeof ext === 'string' ? (ext.trim().startsWith('{') ? JSON.parse(ext) : {}) : (ext || {});
            host = pickHost(cfg.site);
            seedCreds(cfg);
        },

        home() {
            const $ = load(get('/'));
            // 同 Java：跳过 id 0 与含 115 的分类，最多 7 个
            const classes = o.classes($).filter(([id, name]) => id && id !== '0' && name && !name.includes('115')).slice(0, 7)
                .map(([type_id, type_name]) => ({ type_id, type_name }));
            return JSON.stringify({ class: classes, filters: FILTERS, list: vods($, o.homeItems, o.item) });
        },

        homeVod() { return JSON.stringify({ list: [] }); },

        category(tid, pg, filter, extend) {
            const e = extend || {};
            const seg = k => (e[k] ? `/${k}/${encodeURIComponent(e[k])}` : '');
            const path = `/index.php/vod/show/id/${e.cateId || tid}/page/${pg}${seg('class')}${seg('area')}${seg('lang')}${seg('year')}${seg('by')}.html`;
            const list = vods(load(get(path)), '.module-item', o.item);
            const page = parseInt(pg) || 1;
            return JSON.stringify({ list, page, pagecount: list.length ? page + 1 : page });
        },

        detail(id) {
            const $ = load(get(id));
            // 同 Java：只收 Pan.java 正则认得的分享链接，按 panOrder 排序；同一链接页面上会出现两次
            const links = [...new Set(o.links($))]
                .filter(isShare).sort((a, b) => panRank(a) - panRank(b));
            const v = o.vod($, label => o.info($, label));
            // 同 Java processVodData：简介去 [..] 与空格，播放串去 [1234] 样式的数字标记
            v.vod_content = (v.vod_content || '').replace(/\[.*?\]/g, '').replace(/ /g, '').trim();
            return JSON.stringify({ list: [{ vod_id: id, ...v, vod_play_from: playFrom(links), vod_play_url: playUrl(links).replace(/\[\d{4,8}\]/g, '') }] });
        },

        // ponytail: Java 搜索不分页（只取第 1 页），这里同样忽略 pg
        search(key) {
            const list = vods(load(get(`/index.php/vod/search/wd/${encodeURIComponent(key)}.html`)), o.searchItems, o.searchItem);
            return JSON.stringify({ list, page: 1, pagecount: 1 });
        },

        play(flag, id) { return play(flag, id); },
    };
}

export default make();
