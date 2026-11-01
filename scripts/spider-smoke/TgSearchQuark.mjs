// TgSearchQuark.js：pansou 搜索（cloud_types=quark）返回分享链接，首个能列出的结果 detail 出 quark 线路。
const KEYS = ['流浪地球', '庆余年', '三体', '短剧'];

export default async (s, assert) => {
    for (const key of KEYS) {
        const list = (await s.search(key, false, '1')).list || [];
        for (const v of list.slice(0, 5)) {
            assert.ok(/^https?:\/\//.test(v.vod_id) && v.vod_name, JSON.stringify(v));
            const d = (await s.detail(v.vod_id)).list[0];
            if (d.vod_play_from && d.vod_play_from.startsWith('quark')) {
                return `${key}: ${list.length} 条, ${v.vod_name.slice(0, 20)} -> ${d.vod_play_url.split('$$$')[0].split('#').length} 集`;
            }
        }
    }
    assert.fail('没有搜索结果能列出 quark 分享');
};
