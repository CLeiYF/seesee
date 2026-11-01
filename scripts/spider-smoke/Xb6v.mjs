// Xb6v.js：首页、分类、搜索（POST 后读 Location 的 searchid）、详情含磁力/在线/夸克线路，在线播放能取到直链。
export default async (s, assert) => {
    const h = await s.home(true);
    assert.ok(h.class.length > 0 && h.list.length > 0, '首页');
    const c = await s.category(h.class[0].type_id, '2', false, {});
    assert.ok(c.list.length > 0 && c.pagecount >= 2, '分类第 2 页');
    const r = await s.search('流浪地球', false, '1');
    assert.ok(r.list.length > 0 && r.list.some(v => v.vod_name.includes('流浪地球')), '搜索');
    const d = (await s.detail(r.list[0].vod_id)).list[0];
    const froms = d.vod_play_from.split('$$$'), urls = d.vod_play_url.split('$$$');
    assert.ok(froms.length > 0 && d.vod_name, '详情线路');
    const i = froms.findIndex(f => f.includes('播放'));
    assert.ok(i >= 0, '在线播放线路: ' + d.vod_play_from);
    const p = await s.play(froms[i], urls[i].split('#')[0].split('$')[1]);
    assert.ok(/^https?:\/\/.+\.(m3u8|mp4)/.test(p.url) && p.parse === 0, '在线播放: ' + JSON.stringify(p));
    return `${d.vod_name}: ${froms.join(' | ')}`;
};
