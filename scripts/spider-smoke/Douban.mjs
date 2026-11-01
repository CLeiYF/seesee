export const ext = 'https://15414.kstore.space/TVBox/douban.json';
export default async (s, assert) => {
  const h = await s.home(true);
  assert.equal(h.class.length, 7);
  assert.ok(h.list[0].vod_id.startsWith('msearch:') && h.filters.hot_gaia);
  for (const t of ['hot_gaia', 'tv_hot', 'movie', 'rank_list_tv']) assert.ok((await s.category(t, '1', true, {})).list.length, t);
  return `${h.list.length} hot, ${h.list[0].vod_name}`;
};
