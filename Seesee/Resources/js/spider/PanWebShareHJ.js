// 内置花卷，对应 itv 单线路包 custom_spider_modified.jar 的 csp_PanWebShareHJ。
// 与 csp_PanWebShare 流程相同（见 PanWebShare.js），只是站点换了 mxpro 主题，选择器不同。
import { make, pic } from './PanWebShare.js';

// 同 Java i()/j2()：.module-info-tag-link a 中 href 含 key 的链接文字
const tagLinks = ($, key) => $('.module-info-tag-link a').toArray().filter(a => ($(a).attr('href') || '').includes(key)).map(a => $(a).text().trim());

export default make({
    // 首页分类：导航 a.links 的 /id/N.html
    classes: $ => $('li.navbar-item a.links').toArray().map(e => {
        const m = ($(e).attr('href') || '').match(/\/id\/([^/.]+)\.html/);
        return [m && m[1], $(e).attr('title')];
    }),
    // Java 为 .module-main.tab-list 下的海报；现站点首页已无 .tab-list，放宽为全部海报
    links: $ => $('.down-card-url').toArray().map(e => $(e).attr('href') || ''),
    homeItems: '.module-main .module-poster-item.module-item',
    item: ($, e) => {
        const img = $(e).find('.module-item-pic img');
        return { vod_id: $(e).attr('href'), vod_name: $(e).attr('title') || '', vod_pic: pic(img.attr('data-original') || img.attr('data-src')),
            vod_remarks: $(e).find('.module-item-note').text().trim() };
    },
    searchItems: '.module-card-item, .module-item',
    searchItem: ($, e) => ({
        vod_id: $(e).find('.module-card-item-poster').attr('href'), vod_name: $(e).find('.module-card-item-title a').text().trim(),
        vod_pic: pic($(e).find('.module-item-pic img').attr('data-original')), vod_remarks: $(e).find('.module-item-note').text().trim(),
    }),
    // 同 Java h()：整行文字含 label 的 .module-info-item，取其中 a 的文字
    info: ($, label) => {
        const row = $('.module-info-item').toArray().find(e => $(e).text().includes(label));
        return row ? $(row).find('a').toArray().map(a => $(a).text().trim()).join(',') : '';
    },
    vod: ($, info) => ({
        vod_name: $('.module-info-heading h1').first().text().trim(),
        vod_pic: pic($('.module-info-poster img').first().attr('data-original')),
        vod_area: tagLinks($, '/area/')[0] || '', type_name: tagLinks($, '/class/').join(','),
        vod_year: info('上映'), vod_director: info('导演'), vod_actor: info('主演'), vod_remarks: info('集数'),
        vod_content: $('.module-info-introduction-content p').text(),
    }),
});
