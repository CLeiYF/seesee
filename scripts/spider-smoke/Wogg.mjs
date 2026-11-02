// ext 取自 itv local_java.json 的「玩偶 | 4K」；不带网盘凭证，只验证到拿出分享线路
export const ext = JSON.stringify({ site: ['http://www.wogg.live', 'http://woggpan.888484.xyz', 'https://wogg.xxooo.cf', 'https://woggpan.xxooo.cf'] });
export default async (s, assert) => {
  const h = await s.home(true);
  assert.ok(h.class.length === 7 && h.list.length, 'home');
  assert.ok(h.filters['1'].length === 4, 'filters');
  const c = await s.category('1', '1', true, { year: '2025' });
  assert.ok(c.list.length && c.list[0].vod_id.startsWith('/voddetail/'), 'category');
  assert.ok((await s.category('2', '2', true, {})).list.length, 'category p2');
  const d = (await s.detail(c.list[0].vod_id)).list[0];
  assert.ok(d.vod_name, 'detail name');
  const sr = await s.search(d.vod_name.slice(0, 2), false, '1');
  assert.ok(sr.list.length, 'search');
  return `${c.list[0].vod_name}: from=[${d.vod_play_from}] search ${sr.list.length}`;
};
