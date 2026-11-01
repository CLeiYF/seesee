export default async (s, assert) => {
  const h = await s.home(true);
  assert.ok(h.class.length && h.list.length, 'home');
  const tid = h.class[1].type_id;
  assert.ok(tid && h.filters[tid].length === 4, 'filters');
  assert.ok((await s.category(tid, '1', true, { area: '日本' })).list.length, 'category');
  assert.ok((await s.category('', '2', true, {})).list.length, 'category p2');
  const d = (await s.detail(h.list[0].vod_id)).list[0];
  assert.ok(d.vod_name && d.vod_play_url, 'detail');
  assert.ok((await s.search(d.vod_name.slice(0, 2), false)).list.length, 'search');
  const ep = d.vod_play_url.split('$$$')[0].split('#')[0].split('$')[1];
  const p = await s.play(d.vod_play_from.split('$$$')[0], ep, []);
  assert.ok(p.parse === 1 && req(p.url, { headers: p.header }).content.includes('player_aaaa'), 'play ' + p.url);
  return `${h.class.length} classes, ${d.vod_name} -> ${p.url}`;
};
