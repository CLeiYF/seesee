// ext 为空（同 itv local_java.json 的「移动」）；不带移动云盘凭证，只验证到拿出分享线路
export default async (s, assert) => {
  assert.ok((await s.home(true)).class.length === 3, 'home');
  const c = await s.category('1', '1', true, {});
  assert.ok(c.list.length && c.pagecount > 1, 'category');
  assert.ok((await s.category('2', '2', true, {})).list.length, 'category p2');
  let d;
  for (const v of c.list.slice(0, 6)) { d = (await s.detail(v.vod_id)).list[0]; if (d && d.vod_play_from) break; }
  assert.ok(d && d.vod_name && d.vod_play_from, 'detail play_from');
  const sr = await s.search(d.vod_name.slice(0, 2), false, '1');
  assert.ok(sr.list.length, 'search');
  return `${d.vod_name}: from=[${d.vod_play_from}] search ${sr.list.length}`;
};
