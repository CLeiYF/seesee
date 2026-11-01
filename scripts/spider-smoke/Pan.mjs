// 网盘库（Seesee/Resources/js/spider/pan/）：借 Quark.js 的 detail/play（内部走 pan/cloud.js 按链接分发到各盘）。
// 公开分享取自 drpy-node spider/py/_pan/selftest.py；每盘任一候选列出视频即通过。无凭证（ext 与 local 均为空）。
export const spider = 'Quark';

const LIVE = {
    quark: ['https://pan.quark.cn/s/7afba66418d6', 'https://pan.quark.cn/s/c9c30274ad21'],
    uc: ['https://drive.uc.cn/s/b37622addbf04?public=1', 'https://drive.uc.cn/s/43b82dd972a64?public=1'],
    天意: ['https://cloud.189.cn/t/jUNfUnR3Y7vm', 'https://cloud.189.cn/t/eUBFfiieENJv'],
    pan123: ['https://123pan.com/s/7Tx1jv-JwP7v?pwd=xoxo', 'https://123912.com/s/IpPUVv-3urj?pwd=Ocat'],
    阿里: ['https://www.alipan.com/s/5JnzcFFWa6Y'],
    移动: ['https://yun.139.com/shareweb/#/w/i/2qidZRh2H2m6p'],
    BD: ['https://pan.baidu.com/s/1gSUbCQSxjKvJLYYktMcbkA?pwd=p06f'],
};
// 各盘需要凭证的线路：无凭证时应返回空 url + 点名配置 ext 键的 msg
const CRED = { quark: 'ext.cookie', uc: 'ext.uccookie', 天意: 'ext.tianyicookie', pan123: 'ext.pan_auth', 阿里: 'ext.token', 移动: 'ext.yun_cookie', BD: 'ext.baidu_cookie' };

const lines = v => {
    const froms = v.vod_play_from ? v.vod_play_from.split('$$$') : [];
    const urls = v.vod_play_url ? v.vod_play_url.split('$$$') : [];
    return froms.map((f, i) => [f, urls[i].split('#').map(e => e.split('$'))]);
};

export default async (s, assert) => {
    const got = [];
    for (const [disk, urls] of Object.entries(LIVE)) {
        let ok = null, err = '';
        for (const u of urls) {
            const v = (await s.detail(u)).list[0];
            const ls = lines(v);
            if (ls.length && ls[0][1].length) { ok = ls; break; }
            err = u;
        }
        assert.ok(ok, `${disk} 未列出公开分享 ${err}`);
        assert.ok(ok.every(([f, eps]) => f.endsWith('#01') && eps.every(([n, id]) => n && id)), `${disk} 线路格式`);
        got.push(`${disk}:${ok[0][1].length}`);

        // 需要凭证的线路（移动取原画；其余取第一条线路）
        const [flag, eps] = ok.find(([f]) => disk !== '移动' || f.includes('原画'));
        const r = await s.play(flag, eps[0][1]);
        assert.equal(r.url, '', `${disk} 无凭证不应返回地址`);
        assert.ok(r.msg && r.msg.includes(CRED[disk]), `${disk} msg 应点名 ${CRED[disk]}: ${r.msg}`);

        if (disk === '移动') {
            const [jf, jeps] = ok.find(([f]) => f.startsWith('移动(极速)'));
            const p = await s.play(jf, jeps[0][1]);
            assert.ok(p.parse === 0 && /^https?:\/\//.test(p.url), `移动(极速) 匿名播放: ${p.msg || JSON.stringify(p)}`);
            got.push('移动极速播放ok');
        }
    }
    // 多链接 + 不支持的链接：只展开支持的
    const v = (await s.detail(LIVE.移动[0] + ',https://example.com/none')).list[0];
    assert.equal(lines(v).length, 2);
    return got.join(' ');
};
