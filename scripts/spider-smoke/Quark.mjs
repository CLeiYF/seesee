// Quark.js：detail(公开分享) 列出视频；ext 为空时需凭证的线路返回提示 ext.cookie 的 msg。
const SHARE = 'https://pan.quark.cn/s/7afba66418d6';

export default async (s, assert) => {
    const v = (await s.detail(SHARE)).list[0];
    const froms = v.vod_play_from.split('$$$'), urls = v.vod_play_url.split('$$$');
    assert.ok(froms.length && froms.every(f => f.startsWith('quark')), v.vod_play_from);
    const eps = urls[0].split('#');
    assert.ok(eps.length > 0 && eps[0].includes('$'));
    const i = Math.max(0, froms.findIndex(f => f.includes('原画')));
    const r = await s.play(froms[i], urls[i].split('#')[0].split('$')[1]);
    assert.equal(r.url, '');
    assert.ok(r.msg.includes('ext.cookie'), r.msg);
    // ext 提供（假的）cookie 后不再报缺凭证，而是真实请求失败的提示
    await s.init('__dummy=1');
    const r2 = await s.play(froms[i], urls[i].split('#')[0].split('$')[1]);
    await s.init('');
    assert.ok(r2.url === '' && r2.msg && !r2.msg.includes('配置未提供'), r2.msg);
    return `${froms.length} 线路 ${eps.length} 集，msg: ${r.msg}`;
};
