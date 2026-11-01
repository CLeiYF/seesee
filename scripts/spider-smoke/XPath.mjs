// 规则取自 drpy-node spider/py/XPath通用.py 的 EXT（MacCMS conch 模板站 动漫MIKU）
export const H = 'https://www.dmmiku.com';
export const EXT = {
    homeUrl: H + '/index.php/vod/show/id/20.html',
    cateNode: "//div[@id='hl02']//a[contains(@href,'/class/')]", cateName: '/text()', cateId: '/@href', cateIdR: '/class/([^/]+)/',
    homeVodNode: "//li[contains(@class,'vodlist_item')]", homeVodName: '/a/@title', homeVodId: '/a/@href', homeVodIdR: '/id/(\\d+)\\.html',
    homeVodImg: '/a/@data-original', homeVodMark: "//span[contains(@class,'pic_text')]/text()",
    cateUrl: H + '/index.php/vod/show/class/{cateId}/id/20/page/{catePg}.html',
    cateVodNode: "//li[contains(@class,'vodlist_item')]", cateVodName: '/a/@title', cateVodId: '/a/@href', cateVodIdR: '/id/(\\d+)\\.html',
    cateVodImg: '/a/@data-original', cateVodMark: "//span[contains(@class,'pic_text')]/text()",
    dtUrl: H + '/index.php/vod/detail/id/{vid}.html', dtNode: '//body',
    dtName: "//h2[contains(@class,'title')]", dtImg: "//a[contains(@class,'vodlist_thumb')]/@data-original",
    dtYear: "//li[contains(@class,'data')][1]", dtYearR: '年份：(\\d+)', dtArea: "//li[contains(@class,'data')][1]", dtAreaR: '地区：(\\S+)',
    dtMark: "//li[contains(@class,'data')][2]", dtMarkR: '状态：(.*)', dtActor: "//li[contains(@class,'data')][3]", dtActorR: '主演：(.*)',
    dtDirector: "//li[contains(@class,'data')][4]", dtDirectorR: '导演：(.*)', dtDesc: "//div[contains(@class,'content_desc')]/span",
    dtFromNode: "//div[contains(@class,'play_source_tab')]/a", dtFromName: '/@alt',
    dtUrlNode: "//ul[contains(@class,'content_playlist')]", dtUrlSubNode: '//li/a', dtUrlName: '/text()', dtUrlId: '/@href',
    playUrl: H + '{playUrl}',
    searchUrl: H + '/index.php/vod/search.html?wd={wd}&submit=',
    scVodNode: "//li[contains(@class,'searchlist_item')]", scVodName: "//a[contains(@class,'vodlist_thumb')]/@title",
    scVodId: "//a[contains(@class,'vodlist_thumb')]/@href", scVodIdR: '/id/(\\d+)\\.html',
    scVodImg: "//a[contains(@class,'vodlist_thumb')]/@data-original", scVodMark: "//span[contains(@class,'pic_text')]/text()",
};
export const ext = JSON.stringify(EXT);

// 对应 XPath通用.py 的 smoke()，返回 {h, d, p}
export async function smoke(s, assert) {
    const h = await s.home(true);
    assert.ok(h.class.length && h.list.length, 'home');
    assert.ok((await s.category(h.class[0].type_id, '2', true, {})).list.length, 'category');
    const d = (await s.detail(h.list[0].vod_id)).list[0];
    assert.ok(d.vod_name && d.vod_play_url && d.vod_play_from.split('$$$').length === d.vod_play_url.split('$$$').length, 'detail');
    assert.ok((await s.search(d.vod_name.slice(0, 2), false)).list.length, 'search');
    const ep = d.vod_play_url.split('$$$')[0].split('#')[0].split('$')[1];
    const p = await s.play(d.vod_play_from.split('$$$')[0], ep, []);
    assert.ok(p.url.startsWith('http'), 'play ' + p.url);
    return { h, d, p };
}

export default async (s, assert) => {
    const { h, d, p } = await smoke(s, assert);
    assert.equal(p.parse, 1);
    return `${h.class.length} classes, ${d.vod_name} ${d.vod_play_from} -> ${p.url.slice(0, 60)}`;
};
