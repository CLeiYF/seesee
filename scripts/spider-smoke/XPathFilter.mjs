// 规则取自 XPathFilter通用.py：XPath通用 的 EXT，cateUrl 换成带 {area}/{year} 占位符的筛选地址
import { EXT, H, smoke } from './XPath.mjs';
export const FILTER_EXT = { ...EXT, cateUrl: H + '/index.php/vod/show/area/{area}/class/{cateId}/id/20/year/{year}/page/{catePg}.html' };
export const ext = JSON.stringify(FILTER_EXT);

// 筛选与不筛选结果应不同
export async function filtered(s, assert, tid) {
    const a = (await s.category(tid, '1', true, { area: '日本', year: '2023' })).list;
    const b = (await s.category(tid, '1', true, {})).list;
    assert.ok(a.length && b.length && JSON.stringify(a) !== JSON.stringify(b), `filter ${a.length}/${b.length}`);
    return a;
}

export default async (s, assert) => {
    const { h, d, p } = await smoke(s, assert);
    const a = await filtered(s, assert, h.class[0].type_id);
    return `${h.class.length} classes, filtered ${a.length}, ${d.vod_name} -> ${p.url.slice(0, 60)}`;
};
