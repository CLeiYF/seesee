// 内置玩偶，对应 itv 单线路包 custom_spider_modified.jar 的 csp_Wogg（覆盖开源 Wogg.java，改版站点结构）。
// 详情页 .module-row-text 的 data-clipboard-text 为网盘分享链接，交给 pan/cloud.js 列目录。
import { load } from 'assets://js/lib/cat.js';
import { seedCreds, playFrom, playUrl, play, isShare } from './pan/cloud.js';

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36';
const CLASSES = [['44', '臻彩视觉'], ['1', '玩偶电影'], ['2', '玩偶剧集'], ['3', '动漫'], ['4', '综艺'], ['5', '音乐'], ['6', '短剧']];
const FILTERS = {"1":[{"key":"class","name":"剧情","value":[{"n":"全部","v":""},{"n":"喜剧","v":"喜剧"},{"n":"爱情","v":"爱情"},{"n":"恐怖","v":"恐怖"},{"n":"动作","v":"动作"},{"n":"科幻","v":"科幻"},{"n":"剧情","v":"剧情"},{"n":"战争","v":"战争"},{"n":"警匪","v":"警匪"},{"n":"犯罪","v":"犯罪"},{"n":"古装","v":"古装"},{"n":"奇幻","v":"奇幻"},{"n":"武侠","v":"武侠"},{"n":"冒险","v":"冒险"},{"n":"枪战","v":"枪战"},{"n":"恐怖","v":"恐怖"},{"n":"悬疑","v":"悬疑"},{"n":"惊悚","v":"惊悚"},{"n":"历史","v":"历史"}]},{"key":"area","name":"地区","value":[{"n":"全部","v":""},{"n":"中国大陆","v":"中国大陆"},{"n":"中国香港","v":"中国香港"},{"n":"中国台湾","v":"中国台湾"},{"n":"美国","v":"美国"},{"n":"法国","v":"法国"},{"n":"英国","v":"英国"},{"n":"日本","v":"日本"},{"n":"韩国","v":"韩国"},{"n":"德国","v":"德国"},{"n":"泰国","v":"泰国"},{"n":"印度","v":"印度"},{"n":"意大利","v":"意大利"},{"n":"西班牙","v":"西班牙"},{"n":"加拿大","v":"加拿大"},{"n":"其他","v":"其他"}]},{"key":"year","name":"年份","value":[{"n":"全部","v":""},{"n":"2026","v":"2026"},{"n":"2025","v":"2025"},{"n":"2024","v":"2024"},{"n":"2023","v":"2023"},{"n":"2022","v":"2022"},{"n":"2021","v":"2021"},{"n":"2020","v":"2020"},{"n":"2019","v":"2019"},{"n":"2018","v":"2018"},{"n":"2017","v":"2017"},{"n":"2016","v":"2016"},{"n":"2015","v":"2015"},{"n":"2014","v":"2014"},{"n":"2013","v":"2013"},{"n":"2012","v":"2012"},{"n":"2011","v":"2011"},{"n":"2010","v":"2010"}]},{"key":"by","name":"排序","value":[{"n":"时间","v":"time"},{"n":"人气","v":"hits"},{"n":"评分","v":"score"}]}],"2":[{"key":"class","name":"剧情","value":[{"n":"全部","v":""},{"n":"喜剧","v":"喜剧"},{"n":"爱情","v":"爱情"},{"n":"恐怖","v":"恐怖"},{"n":"动作","v":"动作"},{"n":"科幻","v":"科幻"},{"n":"剧情","v":"剧情"},{"n":"战争","v":"战争"},{"n":"警匪","v":"警匪"},{"n":"犯罪","v":"犯罪"},{"n":"古装","v":"古装"},{"n":"奇幻","v":"奇幻"},{"n":"武侠","v":"武侠"},{"n":"冒险","v":"冒险"},{"n":"枪战","v":"枪战"},{"n":"悬疑","v":"悬疑"},{"n":"惊悚","v":"惊悚"},{"n":"历史","v":"历史"}]},{"key":"area","name":"地区","value":[{"n":"全部","v":""},{"n":"中国大陆","v":"中国大陆"},{"n":"中国香港","v":"中国香港"},{"n":"中国台湾","v":"中国台湾"},{"n":"美国","v":"美国"},{"n":"法国","v":"法国"},{"n":"英国","v":"英国"},{"n":"日本","v":"日本"},{"n":"韩国","v":"韩国"},{"n":"德国","v":"德国"},{"n":"泰国","v":"泰国"},{"n":"印度","v":"印度"},{"n":"意大利","v":"意大利"},{"n":"西班牙","v":"西班牙"},{"n":"加拿大","v":"加拿大"},{"n":"其他","v":"其他"}]},{"key":"year","name":"年份","value":[{"n":"全部","v":""},{"n":"2026","v":"2026"},{"n":"2025","v":"2025"},{"n":"2024","v":"2024"},{"n":"2023","v":"2023"},{"n":"2022","v":"2022"},{"n":"2021","v":"2021"},{"n":"2020","v":"2020"},{"n":"2019","v":"2019"},{"n":"2018","v":"2018"},{"n":"2017","v":"2017"},{"n":"2016","v":"2016"},{"n":"2015","v":"2015"},{"n":"2014","v":"2014"},{"n":"2013","v":"2013"},{"n":"2012","v":"2012"},{"n":"2011","v":"2011"},{"n":"2010","v":"2010"}]},{"key":"by","name":"排序","value":[{"n":"时间","v":"time"},{"n":"人气","v":"hits"},{"n":"评分","v":"score"}]}],"3":[{"key":"area","name":"地区","value":[{"n":"全部","v":""},{"n":"大陆","v":"大陆"},{"n":"美国","v":"美国"},{"n":"英国","v":"英国"},{"n":"日本","v":"日本"}]},{"key":"year","name":"年份","value":[{"n":"全部","v":""},{"n":"2026","v":"2026"},{"n":"2025","v":"2025"},{"n":"2024","v":"2024"},{"n":"2023","v":"2023"},{"n":"2022","v":"2022"},{"n":"2021","v":"2021"},{"n":"2020","v":"2020"},{"n":"2019","v":"2019"},{"n":"2018","v":"2018"},{"n":"2017","v":"2017"},{"n":"2016","v":"2016"},{"n":"2015","v":"2015"},{"n":"2014","v":"2014"},{"n":"2013","v":"2013"},{"n":"2012","v":"2012"},{"n":"2011","v":"2011"},{"n":"2010","v":"2010"},{"n":"2009","v":"2009"},{"n":"2008","v":"2008"},{"n":"2007","v":"2007"},{"n":"2006","v":"2006"},{"n":"2005","v":"2005"},{"n":"2004","v":"2004"}]},{"key":"by","name":"排序","value":[{"n":"时间","v":"time"},{"n":"人气","v":"hits"},{"n":"评分","v":"score"}]}],"44":[{"key":"area","name":"地区","value":[{"n":"全部","v":""},{"n":"中国大陆","v":"中国大陆"},{"n":"中国香港","v":"中国香港"},{"n":"中国台湾","v":"中国台湾"},{"n":"美国","v":"美国"},{"n":"法国","v":"法国"},{"n":"英国","v":"英国"},{"n":"日本","v":"日本"},{"n":"韩国","v":"韩国"}]},{"key":"year","name":"年份","value":[{"n":"全部","v":""},{"n":"2026","v":"2026"},{"n":"2025","v":"2025"},{"n":"2024","v":"2024"},{"n":"2023","v":"2023"},{"n":"2022","v":"2022"},{"n":"2021","v":"2021"},{"n":"2020","v":"2020"},{"n":"2019","v":"2019"},{"n":"2018","v":"2018"},{"n":"2017","v":"2017"},{"n":"2016","v":"2016"},{"n":"2015","v":"2015"},{"n":"2014","v":"2014"},{"n":"2013","v":"2013"},{"n":"2012","v":"2012"},{"n":"2011","v":"2011"},{"n":"2010","v":"2010"},{"n":"2009","v":"2009"},{"n":"2008","v":"2008"},{"n":"2007","v":"2007"},{"n":"2006","v":"2006"},{"n":"2005","v":"2005"},{"n":"2004","v":"2004"}]},{"key":"by","name":"排序","value":[{"n":"时间","v":"time"},{"n":"人气","v":"hits"},{"n":"评分","v":"score"}]}],"4":[{"key":"area","name":"地区","value":[{"n":"全部","v":""},{"n":"中国大陆","v":"中国大陆"},{"n":"中国香港","v":"中国香港"},{"n":"中国台湾","v":"中国台湾"},{"n":"美国","v":"美国"},{"n":"法国","v":"法国"},{"n":"英国","v":"英国"},{"n":"日本","v":"日本"},{"n":"韩国","v":"韩国"}]},{"key":"year","name":"年份","value":[{"n":"全部","v":""},{"n":"2026","v":"2026"},{"n":"2025","v":"2025"},{"n":"2024","v":"2024"},{"n":"2023","v":"2023"},{"n":"2022","v":"2022"},{"n":"2021","v":"2021"},{"n":"2020","v":"2020"},{"n":"2019","v":"2019"},{"n":"2018","v":"2018"},{"n":"2017","v":"2017"},{"n":"2016","v":"2016"},{"n":"2015","v":"2015"},{"n":"2014","v":"2014"},{"n":"2013","v":"2013"},{"n":"2012","v":"2012"},{"n":"2011","v":"2011"},{"n":"2010","v":"2010"},{"n":"2009","v":"2009"},{"n":"2008","v":"2008"},{"n":"2007","v":"2007"},{"n":"2006","v":"2006"},{"n":"2005","v":"2005"},{"n":"2004","v":"2004"}]},{"key":"by","name":"排序","value":[{"n":"时间","v":"time"},{"n":"人气","v":"hits"},{"n":"评分","v":"score"}]}],"6":[{"key":"year","name":"年份","value":[{"n":"全部","v":""},{"n":"2026","v":"2026"},{"n":"2025","v":"2025"},{"n":"2024","v":"2024"},{"n":"2023","v":"2023"},{"n":"2022","v":"2022"},{"n":"2021","v":"2021"},{"n":"2020","v":"2020"},{"n":"2019","v":"2019"},{"n":"2018","v":"2018"},{"n":"2017","v":"2017"},{"n":"2016","v":"2016"},{"n":"2015","v":"2015"},{"n":"2014","v":"2014"},{"n":"2013","v":"2013"},{"n":"2012","v":"2012"},{"n":"2011","v":"2011"},{"n":"2010","v":"2010"}]},{"key":"by","name":"排序","value":[{"n":"时间","v":"time"},{"n":"人气","v":"hits"},{"n":"评分","v":"score"}]}]};
// 同单线路包 config.json 的 panOrder
const PAN_ORDER = ['pan.baidu.com', 'drive.uc.cn', 'pan.quark.cn', 'pan.xunlei.com', 'guangyapan.com', 'cloud.189.cn', '123pan|123684|123865|123912', 'aliyundrive.com|alipan.com', 'caiyun.139.com'];
let host = '';

const get = path => req(host + path, { headers: { 'User-Agent': UA, Referer: host + '/' }, timeout: 15000 }).content || '';
const panRank = u => { const i = PAN_ORDER.findIndex(p => p.split('|').some(x => u.includes(x))); return i < 0 ? 99 : i; };

// 豆瓣图片要带 Referer 才能加载（同 Java 的 @Headers= 后缀）
function pic(src) {
    const i = (src || '').lastIndexOf('http');
    const u = i >= 0 ? src.slice(i) : (src || '');
    return u.includes('douban') ? u + '@Headers=' + JSON.stringify({ 'User-Agent': UA, Referer: 'https://www.douban.com' }) : u;
}

function vods($, items) {
    return items.toArray().map(e => {
        const a = $(e).find('.module-item-titlebox > a');
        return { vod_id: a.attr('href'), vod_name: a.attr('title') || '', vod_pic: pic($(e).find('.module-item-pic img').attr('data-src')), vod_remarks: $(e).find('.module-item-text').text().trim() };
    }).filter(v => v.vod_id && v.vod_name !== '臻彩');
}

// 同 Java h()：.video-info-item 中标题含 label 的那行，取其中 a 的文字
function info($, label) {
    const row = $('.video-info-item').toArray().find(e => $(e).children().first().text().includes(label));
    return row ? $(row).find('a').toArray().map(a => $(a).text().trim()).join(',') : '';
}

function pickHost(sites) {
    const list = [].concat(sites || []).map(s => String(s).trim()).filter(Boolean);
    for (const u of list) {
        const code = req(u, { method: 'head', timeout: 5000 }).code;
        if (code >= 200 && code < 400) return u.replace(/\/$/, '');
    }
    return (list[0] || 'http://www.wogg.live').replace(/\/$/, '');
}

export default {
    // ext: {site: [...], cookie, uccookie, ...}；网盘凭证同 Cloud.java
    init(ext) {
        const cfg = typeof ext === 'string' ? (ext.trim().startsWith('{') ? JSON.parse(ext) : {}) : (ext || {});
        host = pickHost(cfg.site);
        seedCreds(cfg);
    },

    home() {
        const $ = load(get('/'));
        const list = vods($, $('.module-item')).slice(0, 12);
        return JSON.stringify({ class: CLASSES.map(([type_id, type_name]) => ({ type_id, type_name })), filters: FILTERS, list });
    },

    homeVod() { return JSON.stringify({ list: [] }); },

    category(tid, pg, filter, extend) {
        const e = extend || {};
        const id = e.cateId || tid;
        const path = `/vodshow/${id}-${e.area || ''}-${e.by || ''}-${e.class || ''}-----${pg}---${e.year || ''}.html`;
        const $ = load(get(path));
        const list = vods($, $('.module-item'));
        const page = parseInt(pg) || 1;
        return JSON.stringify({ list, page, pagecount: list.length ? page + 1 : page });
    },

    detail(id) {
        const $ = load(get(id));
        // 同 Java：只取阿里/夸克/UC，百度排在后面，再按 panOrder 排序；同一链接页面上会出现两次
        const links = [...new Set($('.module-row-text').toArray().map(e => $(e).attr('data-clipboard-text') || ''))]
            .filter(u => isShare(u) && /aliyundrive|alipan|pan\.quark\.cn|drive\.uc\.cn|pan\.baidu\.com/.test(u))
            .sort((a, b) => panRank(a) - panRank(b));
        return JSON.stringify({
            list: [{
                vod_id: id, vod_name: $('.video-info-header > .page-title').first().text().trim(),
                vod_pic: pic($('.module-item-pic img').first().attr('data-src')),
                type_name: $('.video-info-header a.tag-link').last().text().trim(),
                vod_year: info($, '年代'), vod_area: $('.video-info-header div.tag-link a').toArray().map(a => $(a).text().trim()).join(','),
                vod_director: info($, '导演'), vod_actor: info($, '主演'), vod_remarks: info($, '备注'),
                vod_content: $('p.sqjj_a').text().replace(/\[.*?\]/g, '').replace(/ /g, '').trim(),
                vod_play_from: playFrom(links), vod_play_url: playUrl(links).replace(/\[\d{4,8}\]/g, ''),
            }],
        });
    },

    search(key, quick, pg) {
        const $ = load(get(`/index.php/vodsearch/${encodeURIComponent(key)}----------${pg || 1}---.html`));
        const list = $('.module-search-item').toArray().map(e => {
            const a = $(e).find('.video-serial');
            return { vod_id: a.attr('href'), vod_name: a.attr('title') || '', vod_pic: pic($(e).find('.module-item-pic > img').attr('data-src')),
                vod_remarks: $(e).find('.video-info-header a.video-serial').first().text().trim() };
        }).filter(v => v.vod_id);
        return JSON.stringify({ list, page: parseInt(pg || 1) });
    },

    play(flag, id) { return play(flag, id); },
};
