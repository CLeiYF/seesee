// Pan123.js：detail(公开分享) 列出视频；ext 为空时需凭证的线路返回提示 ext.pan_auth 的 msg。
const SHARE = 'https://123pan.com/s/7Tx1jv-JwP7v?pwd=xoxo';

export default async (s, assert) => {
    const v = (await s.detail(SHARE)).list[0];
    const froms = v.vod_play_from.split('$$$'), urls = v.vod_play_url.split('$$$');
    assert.ok(froms.length && froms.every(f => f.startsWith('pan123')), v.vod_play_from);
    const eps = urls[0].split('#');
    assert.ok(eps.length > 0 && eps[0].includes('$'));
    const i = Math.max(0, froms.findIndex(f => f.includes('原画')));
    const r = await s.play(froms[i], urls[i].split('#')[0].split('$')[1]);
    assert.equal(r.url, '');
    assert.ok(r.msg.includes('ext.pan_auth'), r.msg);
    return `${froms.length} 线路 ${eps.length} 集，msg: ${r.msg}`;
};
