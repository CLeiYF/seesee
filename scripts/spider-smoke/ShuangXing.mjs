// ext 为空（同 itv local_java.json 的「双星」）；不带网盘凭证，只验证到拿出分享线路
export default async (s, assert) => {
  assert.ok((await s.home(true)).class.length === 8, 'home');
  const c = await s.category('mv', '1', true, {});
  assert.ok(c.list.length && !c.list[0].vod_name.includes('【'), 'category');
  let d;
  for (const v of c.list.slice(0, 6)) { d = (await s.detail(v.vod_id)).list[0]; if (d.vod_play_from) break; }
  assert.ok(d.vod_name && d.vod_play_from, 'detail play_from');
  const sr = await s.search(c.list[0].vod_name.slice(0, 3), false, '1');
  assert.ok(sr.list.length, 'search');
  return `${d.vod_name}: from=[${d.vod_play_from}] search ${sr.list.length}`;
};
