export const ext = JSON.stringify({ drives: [
  { name: '七米藍', server: 'https://al.chirmyram.com/dav', user: 'alist', pass: 'alist' },
] });
export default async (s, assert) => {
  const h = await s.home(true);
  assert.equal(h.class[0].type_id, '七米藍');
  assert.equal(h.filters['七米藍'].length, 2);
  assert.ok((await s.category('七米藍', '1', true, {})).list.length, 'root');
  let tid = '七米藍/dav/4k1', vod;
  for (let i = 0; i < 6 && !vod; i++) {
    const lst = (await s.category(tid, '1', true, { type: 'name', order: 'asc' })).list;
    assert.ok(lst.length, tid);
    vod = lst.find(v => v.vod_tag === 'file');
    if (!vod) tid = lst.find(v => v.vod_tag === 'folder').vod_id;
  }
  assert.ok(vod, '未找到视频文件');
  const d = (await s.detail(vod.vod_id)).list[0];
  assert.ok(d.vod_play_url, 'detail');
  const p = await s.play(d.vod_play_from, d.vod_play_url.split('#')[0].split('$')[1], []);
  assert.ok(p.parse === 0 && p.header.Authorization, 'play');
  // 只验证鉴权 + URL 拼接：AList 型 WebDAV 会 302 到网盘直链，不跟随
  const r = req(p.url, { headers: { ...p.header, Range: 'bytes=0-15' }, redirect: 0, timeout: 20000 });
  assert.ok([200, 206, 302].includes(r.code), 'status ' + r.code);
  return `${vod.vod_id} -> ${p.url.slice(0, 50)} ${r.code}`;
};
