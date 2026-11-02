// 匿名跑（不带 cookie）；ext 取自 itv 的「少儿｜教育」，再切到「哔哩｜音乐」
export const spider = 'BiliCsp';
export const ext = JSON.stringify({ json: './json/少儿教育.json' });
export default async (s, assert) => {
  const h = await s.home(true);
  assert.ok(h.class.length && h.filters[h.class[0].type_id], 'home');
  const c = await s.category(h.class[0].type_id, '1', true, { duration: '2' });
  assert.ok(c.list.length && /^\d+$/.test(c.list[0].vod_id), 'category');
  const d = (await s.detail(c.list[0].vod_id)).list[0];
  assert.ok(d.vod_name && d.vod_play_url.includes('_'), 'detail');
  const p = await s.play('B站', d.vod_play_url.split('#')[0].split('$')[1], []);
  assert.ok(/^https?:/.test(p.url), 'play');
  assert.ok((await s.search('儿歌', false, '1')).list.length, 'search');
  await s.init(JSON.stringify({ n: '哔哩音乐' }));
  const m = await s.home(true);
  assert.ok(m.class[0].type_id === '演唱会超清', 'music home');
  const mc = await s.category('演唱会超清', '1', true, { tid: '周杰伦演唱会超清' });
  assert.ok(mc.list.length, 'music category');
  return `${h.class.length} classes, ${d.vod_name} -> ${p.url.slice(0, 50)}; music ${mc.list.length}`;
};
