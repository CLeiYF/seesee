export const ext = JSON.stringify({ drives: [
  { name: '七米藍', server: 'https://al.chirmyram.com' },
  { name: '神族九帝', server: 'https://alist.shenzjd.com' },
] });
const MEDIA = ['mp4', 'mkv', 'wmv', 'flv', 'avi', 'iso', 'mpg', 'ts', 'mp3', 'aac', 'flac', 'm4a', 'ape', 'ogg'];
const isMedia = n => MEDIA.includes(n.slice(n.lastIndexOf('.') + 1).toLowerCase());
export default async (s, assert) => {
  const h = await s.home(true);
  assert.deepEqual(h.class.map(c => c.type_id), ['七米藍', '神族九帝']);
  assert.equal(h.filters['七米藍'].length, 2);
  assert.ok((await s.category('七米藍', '1', true, {})).list.length, 'root');
  // 从已知电影目录逐层进入直到找到视频文件
  let tid = '七米藍/mov/电影', vod;
  for (let i = 0; i < 6 && !vod; i++) {
    const lst = (await s.category(tid, '1', true, { type: 'name', order: 'asc' })).list;
    assert.ok(lst.length, tid);
    vod = lst.find(v => v.vod_tag === 'file' && isMedia(v.vod_name));
    if (!vod) tid = lst.find(v => v.vod_tag === 'folder').vod_id;
  }
  assert.ok(vod, '未找到视频文件');
  const d = (await s.detail(vod.vod_id)).list[0];
  assert.ok(d.vod_play_url, 'detail');
  // 上游 OneDrive 偶发限流，多试几集
  let p;
  for (const ep of d.vod_play_url.split('#').slice(0, 5).map(e => e.split('$')[1])) {
    p = await s.play(d.vod_play_from, ep, []);
    if (p.url) break;
  }
  assert.ok(p.url.startsWith('http') && p.parse === 0, 'play ' + p.url);
  const r = (await s.search('复仇', false, '1')).list;
  assert.ok(r.length && r.every(v => v.vod_id.includes('/')), 'search');
  return `${vod.vod_id} -> ${p.url.slice(0, 50)} | search ${r.length}`;
};
