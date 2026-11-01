// 匿名跑（不带 cookie）；登录态由 ext.cookie 提供，冒烟不依赖它
export default async (s, assert) => {
  const h = await s.home(true);
  assert.ok(h.class.length === 8, 'home');
  assert.ok((await s.homeVod()).list.length, 'homeVod');
  const c = await s.category('popular', '1', false, {});
  assert.ok(c.list.length && c.list[0].vod_id.startsWith('BV'), 'popular');
  assert.ok((await s.category('pgc_1', '1', false, {})).list[0].vod_id.startsWith('ss'), 'pgc');
  const d = (await s.detail(c.list[0].vod_id)).list[0];
  assert.ok(d.vod_name && d.vod_play_url.includes('_'), 'detail');
  const p = await s.play('B站', d.vod_play_url.split('#')[0].split('$')[1], []);
  assert.ok(/^https?:/.test(p.url), 'play ugc');
  const sr = await s.search('中国奇谭', false, '1');
  assert.ok(sr.list.length, 'search');
  const ss = (await s.detail((await s.category('pgc_4', '1', false, {})).list[0].vod_id)).list[0];
  assert.ok(ss.vod_play_url, 'season detail');
  return `${c.list[0].vod_name} -> ${p.url.slice(0, 50)}; search ${sr.list.length}`;
};
