// ext 取自 itv local_java.json 的「闪电」；不带网盘凭证，只验证到拿出分享线路（死链常见，试前几部）
export const ext = JSON.stringify({ site: ['http://shandian.blog'] });
export default async (s, assert) => {
  const h = await s.home(true);
  assert.ok(h.class.length && h.list.length, 'home');
  const c = await s.category(h.class[0].type_id, '1', true, { year: '2025' });
  assert.ok(c.list.length, 'category');
  assert.ok((await s.category(h.class[1].type_id, '2', true, {})).list.length, 'category p2');
  let d, n = 0;
  for (const v of c.list.slice(0, 6)) { d = (await s.detail(v.vod_id)).list[0]; n++; if (d.vod_play_from) break; }
  assert.ok(d.vod_name, 'detail name');
  assert.ok(d.vod_play_from, 'detail play_from');
  const sr = await s.search(d.vod_name.slice(0, 2), false, '1');
  assert.ok(sr.list.length, 'search');
  return `${d.vod_name} (第${n}部): from=[${d.vod_play_from}] search ${sr.list.length}`;
};
