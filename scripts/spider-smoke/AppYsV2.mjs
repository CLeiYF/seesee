// 对应 AppYsV2通用.py 的 __main__ 自检；该 v1.vod 接口目前只返回占位影片，播放列表为空，播放只做纯逻辑断言。
export const ext = 'http://jxfmax.juxiafan.com/icciu_api.php/v1.vod';
export default async (s, assert) => {
  const h = await s.home(true);
  assert.ok(h.class.length, 'home');
  const tid = h.class[0].type_id;
  assert.ok(h.filters[tid].some(f => f.key === '排序') && h.filters[tid].some(f => f.key === 'class'), 'filters');
  const c = (await s.category(tid, '1', true, { '排序': 'time' })).list;
  assert.ok(c.length && c[0].vod_id, 'category');
  assert.ok(Array.isArray((await s.homeVod()).list), 'homeVod');
  const d = (await s.detail(c[0].vod_id)).list[0];
  assert.ok(d.vod_name && d.vod_play_from, 'detail');
  assert.ok(Array.isArray((await s.search('爱', false)).list), 'search');
  assert.equal((await s.play('fanqie', 'https://example.com/a/b/index.m3u8', [])).parse, 0);
  assert.equal((await s.play('none', 'https://v.qq.com/x/cover/abc.html', [])).jx, 1);
  // TV 接口：分类来自内置筛选，无需联网
  await s.init('http://h.example/api.php/tv/vod');
  assert.equal((await s.home(true)).class.length, 6);
  return `${h.class.length} classes, ${d.vod_name} ${d.vod_play_from}`;
};
