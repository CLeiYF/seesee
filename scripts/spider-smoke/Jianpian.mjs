export default async (s, assert) => {
  const h = await s.home(true);
  assert.equal(h.class.length, 6);
  assert.ok((await s.homeVod()).list.length, 'homeVod');
  const c = (await s.category('1', '1', true, { by: 'updata' })).list;
  assert.ok(c.length && c[0].vod_pic.startsWith('http'), 'category');
  assert.ok((await s.category('99', '1', true, {})).list.length, 'netflix');
  const d = (await s.detail(c[0].vod_id)).list[0];
  assert.ok(d.vod_name && d.vod_play_url, 'detail');
  assert.ok((await s.search(d.vod_name.slice(0, 2), false)).list.length, 'search');
  const ep = d.vod_play_url.split('$$$')[0].split('#')[0].split('$')[1];
  const p = await s.play(d.vod_play_from.split('$$$')[0], ep, []);
  assert.ok(p.url.startsWith('http') && p.parse === 0, 'play ' + p.url);
  return `${d.vod_name} ${d.vod_play_from.split('$$$').length} lines -> ${p.url.slice(0, 50)}`;
};
