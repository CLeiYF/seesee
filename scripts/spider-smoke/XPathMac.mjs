// 规则取自 XPathMac通用.py：XPath通用 的 EXT + dcPlayUrl/dcVipFlag/pCfgJs
import { EXT, H, smoke } from './XPath.mjs';
export const MAC_EXT = { ...EXT, dcPlayUrl: true, dcVipFlag: true, pCfgJs: H + '/static/js/playerconfig.js' };
export const ext = JSON.stringify(MAC_EXT);

export async function macChecks(s, assert) {
    const r = await smoke(s, assert);
    // playerconfig.js 把 "主播放线路" 映射为 dplayer
    assert.equal(r.d.vod_play_from.split('$$$')[0], 'dplayer', r.d.vod_play_from);
    // 该站 player_aaaa.url 是自研播放器 id（非直链），按 Java 回落到 parse=1 嗅探播放页
    assert.equal(r.p.parse, 1);
    return r;
}

export default async (s, assert) => {
    const { h, d, p } = await macChecks(s, assert);
    return `${h.class.length} classes, ${d.vod_name} ${d.vod_play_from} -> ${p.url.slice(0, 60)}`;
};
