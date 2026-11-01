export default async (s, assert) => {
  const h = await s.home(true);
  assert.ok(h.class.length && h.list.length, 'home');
  const tid = h.class[1].type_id;
  const c1 = (await s.category(tid, '1', false, {})).list, c2 = (await s.category(tid, '2', false, {})).list;
  assert.ok(c1.length && c2.length && c1[0].vod_id !== c2[0].vod_id, 'category');
  const d = (await s.detail(c1[0].vod_id)).list[0];
  assert.ok(d.vod_name && d.vod_play_url && d.vod_year, 'detail');
  assert.ok((await s.search(d.vod_name.slice(0, 2), false)).list.length, 'search');
  const ep = d.vod_play_url.split('$$$')[0].split('#')[0].split('$')[1];
  const p = await s.play(d.vod_play_from.split('$$$')[0], ep, []);
  assert.ok(p.url.startsWith('http'), 'play ' + p.url);
  return `${h.class.length} classes, ${d.vod_name} ${d.vod_play_from} -> ${p.parse} ${p.url.slice(0, 60)}`;
};
