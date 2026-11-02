// boosj.com 需国内网络
export default async (s, assert) => {
  const h = await s.home(true);
  assert.ok(h.class.length === 19 && h.filters['582'].length === 2, 'home');
  const c = await s.category('582', '1', true, {});
  assert.ok(c.list.length && /^\d+$/.test(c.list[0].vod_id), 'category');
  const d = (await s.detail(c.list[0].vod_id)).list[0];
  assert.ok(d.vod_name && d.vod_play_url.includes('$'), 'detail');
  const p = await s.play('童趣', d.vod_play_url.split('$')[1], []);
  assert.ok(/^https?:/.test(p.url), 'play');
  assert.ok((await s.search('儿歌', false, '1')).list.length, 'search');
  return `${d.vod_name} -> ${p.url.slice(0, 50)}`;
};
