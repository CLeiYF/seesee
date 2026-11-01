// 规则取自 XPathMacFilter通用.py：XPathMac 的 EXT + XPathFilter 的筛选 cateUrl
import { MAC_EXT, macChecks } from './XPathMac.mjs';
import { FILTER_EXT, filtered } from './XPathFilter.mjs';
export const ext = JSON.stringify({ ...MAC_EXT, cateUrl: FILTER_EXT.cateUrl });

export default async (s, assert) => {
    const { h, d, p } = await macChecks(s, assert);
    const a = await filtered(s, assert, h.class[0].type_id);
    return `${h.class.length} classes, filtered ${a.length}, ${d.vod_name} ${d.vod_play_from} -> ${p.url.slice(0, 60)}`;
};
