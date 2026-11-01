export default async (s, assert) => {
  const h = await s.home(true);
  assert.equal(h.class.length, 8);
  const c = (await s.category(h.class[1].type_id, '1', false, {})).list;
  assert.ok(c.length && c[0].vod_pic.startsWith('http'), 'category');
  const d = (await s.detail(c[0].vod_id)).list[0];
  assert.ok(d.vod_name, 'detail');
  const r = (await s.search('烫伤', false)).list;
  assert.ok(r.length && r[0].vod_pic.startsWith('https:'), 'search');
  const p = await s.play('Qile', d.vod_play_url.split('$')[1], []);
  assert.ok(p.parse === 0 && p.url.startsWith('http'), 'play ' + p.url);
  return `${c.length} items, ${d.vod_name} -> ${p.url.slice(0, 60)}`;
};
