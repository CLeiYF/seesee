// TgSearch139.js：pansou 搜索（cloud_types=mobile）必须返回移动云盘链接；能否 detail 出视频取决于结果
// （公共实例的移动结果少且时有时无，常见只含 .iso 的分享，按 jar 规则不算视频），只报告不判失败——移动列目录已由 Pan.mjs 硬性验证。
const KEYS = ['无可替代', '短剧', '庆余年', '流浪地球', '无可替代', '短剧'];

export default async (s, assert) => {
    for (const key of KEYS) {
        const list = (await s.search(key, false, '1')).list || [];
        if (!list.length) continue;
        assert.ok(list.every(v => /139\.com/.test(v.vod_id) && v.vod_name), JSON.stringify(list[0]));
        for (const v of list.slice(0, 5)) {
            const d = (await s.detail(v.vod_id)).list[0];
            if (d.vod_play_from.startsWith('移动')) return `${key}: ${list.length} 条, ${v.vod_name.slice(0, 20)} -> ${d.vod_play_url.split('$$$')[0].split('#').length} 集`;
        }
        return `${key}: ${list.length} 条移动链接（前 5 条无可列出的视频，未判失败）`;
    }
    assert.fail('pansou 没有返回任何移动云盘结果');
};
