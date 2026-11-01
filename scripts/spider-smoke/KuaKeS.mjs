// KuaKeS.js：首页、分类、搜索、详情（admin-ajax 换分享链接后列出视频）。
export default async (s, assert) => {
    const h = await s.home(true);
    assert.ok(h.class.length > 0 && h.list.length > 0, '首页');
    const c = await s.category(h.class[0].type_id, '1', false, {});
    assert.ok(c.list.length > 0, '分类 ' + h.class[0].type_id);
    const r = await s.search('流浪地球', false, '1');
    assert.ok(r.list.length > 0, '搜索');
    for (const v of h.list.slice(0, 6)) {
        const d = (await s.detail(v.vod_id)).list[0];
        assert.ok(d.vod_name, '详情名称');
        if (d.vod_play_from) return `${h.class.length} 分类, ${d.vod_name} -> ${d.vod_play_from}`;
    }
    assert.fail('前 6 个详情都没有能列出的网盘分享');
};
