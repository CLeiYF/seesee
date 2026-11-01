// TianYi.js：detail(公开分享) 列出视频；ext 为空时需凭证的线路返回提示 ext.tianyicookie 的 msg。
const SHARE = 'https://cloud.189.cn/t/jUNfUnR3Y7vm';

export default async (s, assert) => {
    const v = (await s.detail(SHARE)).list[0];
    const froms = v.vod_play_from.split('$$$'), urls = v.vod_play_url.split('$$$');
    assert.ok(froms.length && froms.every(f => f.startsWith('天意')), v.vod_play_from);
    const eps = urls[0].split('#');
    assert.ok(eps.length > 0 && eps[0].includes('$'));
    const i = Math.max(0, froms.findIndex(f => f.includes('原画')));
    const r = await s.play(froms[i], urls[i].split('#')[0].split('$')[1]);
    assert.equal(r.url, '');
    assert.ok(r.msg.includes('ext.tianyicookie'), r.msg);
    return `${froms.length} 线路 ${eps.length} 集，msg: ${r.msg}`;
};
