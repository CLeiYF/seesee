export default async (s, assert) => {
  const h = await s.home(true);
  assert.ok(h.class.length && h.list.length, 'home');
  const tid = h.class[0].type_id;
  assert.equal(h.filters[tid]?.length, 3);
  assert.ok((await s.category(tid, '1', true, { by: 'hits' })).list.length, 'category');
  const d = (await s.detail(h.list[0].vod_id)).list[0];
  assert.ok(d.vod_name && d.vod_play_url, 'detail');
  assert.ok((await s.search(h.list[0].vod_name.slice(0, 2), false)).list.length, 'search');
  const ep = d.vod_play_url.split('$$$')[0].split('#')[0].split('$')[1];
  const p = await s.play(d.vod_play_from.split('$$$')[0], ep, []);
  assert.ok(p.url.startsWith('http'), 'play ' + p.url);
  return `${h.class.length} classes, ${d.vod_name} -> ${p.url.slice(0, 60)}`;
};
