// Cloud 帮助函数（移植自 _pan/__init__.py ← spider/Cloud.java）：站点爬虫拿到分享链接后
//   vod_play_from = playFrom(links); vod_play_url = playUrl(links); play(flag, id) 直接转发。
// 每条分享按网盘线路展开，线路名后缀 #序号 保证唯一；解析失败或无视频的分享跳过。
import { PanError, setExtCreds } from './common.js';
import { quark } from './quark.js';
import { uc } from './uc.js';
import { tianyi } from './tianyi.js';
import { yidong } from './yidong.js';
import { baidu } from './baidu.js';
import { pan123 } from './pan123.js';
import { ali } from './ali.js';

// 分发顺序同 Cloud.java（夸克、UC、天翼、移动、百度、123）；阿里在 Java 中被注释，这里放最后
export const CLIENTS = [quark, uc, tianyi, yidong, baidu, pan123, ali];
export { quark, uc, tianyi, yidong, baidu, pan123, ali };

export function clientFor({ url, flag } = {}) {
    return CLIENTS.find(c => (url != null && c.match(url)) || (flag != null && c.ownsFlag(flag))) || null;
}

// ext 键（同 Cloud.java init：cookie / uccookie / tianyicookie；Ali.java 的 token）→ 内部凭证键。
// 其余为本移植新增（jar 里这些盘不读 ext），与内部键同名。
const EXT_KEYS = { cookie: 'quark_cookie', uccookie: 'uc_cookie', token: 'ali_token' };
const EXTRA_KEYS = ['uc_token_cookie', 'ali_open_token', 'pan_auth', 'pan_passport', 'pan_password', 'yun_cookie', 'baidu_cookie'];

function asObject(v) {
    if (v && typeof v === 'object') return v;
    const t = String(v || '').trim();
    if (!t.startsWith('{')) return null;
    try { return JSON.parse(t); } catch { return null; }
}

/**
 * init(ext) 时调用，ext 优先于 local 里的旧值。
 *   Cloud 类站点：ext 为 JSON 对象（{cookie, uccookie, tianyicookie, token, ...}）
 *   单盘爬虫（Quark.js 等）：ext 为原始 cookie/token 字符串，rawKey 指明它对应哪个 ext 键
 * tianyicookie 可为 cookie 串或 {"username","password"}（同 TianyiApi.setCookie）。
 */
export function seedCreds(ext, rawKey) {
    let o = asObject(ext);
    if (!o) {
        const t = typeof ext === 'string' ? ext.trim() : '';
        o = t && rawKey ? { [rawKey]: t } : {};
    }
    const m = {};
    for (const [k, key] of Object.entries(EXT_KEYS)) if (o[k]) m[key] = String(o[k]).trim();
    for (const key of EXTRA_KEYS) if (o[key]) m[key] = String(o[key]).trim();
    if (o.tianyicookie) {
        const t = asObject(o.tianyicookie);
        if (t && t.username && t.password) { m.cloud_account = String(t.username); m.cloud_password = String(t.password); }
        else if (!t) m.cloud_cookie = String(o.tianyicookie).trim();
    }
    setExtCreds(m);
    for (const c of CLIENTS) c.reset?.();
}

/** 是否为已支持网盘的分享链接 */
export const isShare = url => !!clientFor({ url });

let cache = { key: null, value: [] };   // 同 Java：只保留最近一次，from/url 两次调用只解析一次

function fromAndUrl(shareLinks) {
    const links = [].concat(shareLinks || []).map(x => String(x || '').trim()).filter(Boolean);
    const key = links.join('\n');
    if (cache.key === key) return cache.value;
    const result = [];
    links.forEach((link, i) => {
        const cli = clientFor({ url: link });
        if (!cli) return;
        let eps;
        try {
            eps = cli.episodes(link);
        } catch (e) {
            console.log(`网盘解析失败 ${cli.NAME}: ${e.message}`);
            return;
        }
        if (!eps.length) return;
        const url = eps.map(([n, id]) => `${String(n).replace(/[#$]/g, ' ')}$${id}`).join('#');
        const idx = String(i + 1).padStart(2, '0');
        for (const q of cli.qualities()) result.push([`${q}#${idx}`, url]);
    });
    cache = { key, value: result };
    return result;
}

export const playFrom = links => fromAndUrl(links).map(x => x[0]).join('$$$');
export const playUrl = links => fromAndUrl(links).map(x => x[1]).join('$$$');

/** 返回 JSON 字符串；缺凭证或失败时 url 为空、msg 说明原因（App 会展示 msg） */
export function play(flag, id) {
    const cli = clientFor({ flag });
    try {
        if (!cli) throw new PanError('未知网盘线路: ' + flag);
        return JSON.stringify(cli.play(id, flag));
    } catch (e) {
        return JSON.stringify({ parse: 0, url: '', msg: e instanceof PanError ? e.message : `${cli ? cli.NAME : '网盘'}播放失败: ${e.message}` });
    }
}

/** detail(id) 的通用实现：id 为分享链接（可用逗号/空白分隔多个） */
export function shareDetail(id, vod = {}) {
    const links = String(id || '').split(/[\s,]+/).filter(Boolean);
    return { vod_id: id, vod_name: vod.vod_name || links[0] || '', ...vod, vod_play_from: playFrom(links), vod_play_url: playUrl(links) };
}
