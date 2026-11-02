// ext 为空（同 itv local_java.json 的「爱盼」）；不带网盘凭证，只验证到拿出分享线路
export default async (s, assert) => {
  const h = await s.home(true);
  assert.ok(h.class.length === 3, 'home');
  assert.ok((await s.homeVod()).list.length, 'homeVod');
  const c = await s.category('sort=latest', '1', true, {});
  assert.ok(c.list.length && c.pagecount >= 1, 'category');
  // 死链很常见，取前几部里第一个有线路的
  let d;
  for (const v of c.list.slice(0, 6)) { d = (await s.detail(v.vod_id)).list[0]; if (d.vod_play_from) break; }
  assert.ok(d.vod_name && d.vod_play_from, 'detail play_from');
  const sr = await s.search(d.vod_name.slice(0, 2), false, '1');
  assert.ok(sr.list.length, 'search');
  return `${d.vod_name}: from=[${d.vod_play_from}] search ${sr.list.length}`;
};
