// ext 取自 itv local_java.json 的「金牌PY」
export const ext = JSON.stringify({ site: 'https://y2s52n7.com,https://m.hkybqufgh.com,https://m.sizhengxt.com,https://m.9zhoukj.com,https://m.jiabaide.cn' });
export default async (s, assert) => {
  const h = await s.home(true);
  assert.ok(h.class.length, 'home');
  const tid = h.class[0].type_id;
  assert.ok(h.filters[tid].length >= 4, 'filters');
  const c = await s.category(tid, '1', true, {});
  assert.ok(c.list.length && c.list[0].vod_id, 'category');
  assert.ok((await s.homeVod()).list.length, 'homeVod');
  const d = (await s.detail(String(c.list[0].vod_id))).list[0];
  assert.ok(d.vod_name && d.vod_play_url.includes('@@'), 'detail');
  assert.ok((await s.search(d.vod_name.slice(0, 2), false, '1')).list.length, 'search');
  const p = await s.play('金牌', d.vod_play_url.split('#')[0].split('$')[1], []);
  assert.ok(p.url.length >= 2 && /^https?:/.test(p.url[1]), 'play');
  return `${h.class.length} classes, ${d.vod_name} -> ${p.url[1].slice(0, 60)}`;
};
