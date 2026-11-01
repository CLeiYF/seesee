export default async (s, assert) => {
  const h = await s.home(true);
  assert.ok(h.class.length === 4 && h.class.slice(1).every(c => h.filters[c.type_id]), 'home');
  const c = (await s.category('', '1', true, {})).list;
  assert.ok(c.length, 'category');
  assert.ok((await s.category('8', '1', true, { cateId: '8' })).list.length, 'football');
  const live = c.filter(v => v.vod_id !== 'https://www.88kanqiu.tw');
  assert.ok(live.length, 'no live match right now');
  const d = (await s.detail(live[0].vod_id)).list[0];
  assert.ok(d.vod_play_url, 'detail');
  const p = await s.play('Qile', d.vod_play_url.split('#')[0].split('$')[1], []);
  assert.ok(p.url.startsWith('http'), 'play ' + p.url);
  return `${c.length} matches, ${live[0].vod_name.slice(0, 30)} -> ${p.url.slice(0, 60)}`;
};
