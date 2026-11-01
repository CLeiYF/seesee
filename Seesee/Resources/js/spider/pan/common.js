// 网盘库公共部分（移植自 drpy-node spider/py/_pan/common.py）：凭证读写、HTTP、媒体判断、cookie 工具。
// 凭证同 jar：来自站点 ext（远程配置下发，cloud.js 的 seedCreds 解析）；local.get('pan', <键>) 只用于持久化
// 刷新后的值（如夸克 __puus）及 ext 未提供时兜底。ext 有值时以 ext 为准。缺失时 play 抛 CredentialError，cloud.play 转成 msg。
import { Crypto } from 'assets://js/lib/cat.js';

export const CHROME = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
// 同 AndroidCatVodSpider Util.MEDIA
const MEDIA = ['mp4', 'mkv', 'wmv', 'flv', 'avi', 'iso', 'mpg', 'ts', 'mp3', 'aac', 'flac', 'm4a', 'ape', 'ogg',
    'rmvb', 'mov', 'm2ts', 'webm', '3gp'];

export class PanError extends Error {}

/** 缺少凭证：消息直接给用户看，点名配置 ext 里的键 */
export class CredentialError extends PanError {
    constructor(disk, what, ...extKeys) {
        super(`配置未提供${disk} ${what}（${extKeys.map(k => 'ext.' + k).join(' 或 ')}）`);
    }
}

let extCreds = {};
/** 用站点 ext 解析出的凭证覆盖（键为内部键名，如 quark_cookie） */
export const setExtCreds = map => { extCreds = { ...map }; };
export const cred = key => extCreds[key] || local.get('pan', key) || '';
/** 刷新后的凭证：本次会话立即生效，并持久化到 local */
export function setCred(key, value) {
    if (key in extCreds) extCreds[key] = value || '';
    local.set('pan', key, value || '');
}

export const ext = name => (name && name.includes('.') ? name.split('.').pop().toLowerCase() : '');
export const isMedia = name => MEDIA.includes(ext(name || ''));

/** 同 Util.getSize */
export function getSize(size) {
    size = Number(size) || 0;
    if (size <= 0) return '';
    for (const [unit, base] of [['TB', 1024 ** 4], ['GB', 1024 ** 3], ['MB', 1024 ** 2], ['KB', 1024]]) {
        if (size > base) return (size / base).toFixed(2) + unit;
    }
    return size.toFixed(2) + 'B';
}

/** 从链接里提取 pwd= / 提取码 / 访问码 */
export function queryPwd(url) {
    const m = /(?:[?&#]pwd=|提取码[:：]?\s*|访问码[:：]?\s*|password=)([A-Za-z0-9]+)/.exec(url || '');
    return m ? m[1] : '';
}

export const qs = o => Object.entries(o).map(([k, v]) => encodeURIComponent(k) + '=' + encodeURIComponent(v ?? '')).join('&');

/** 同步请求；body 为对象时按 JSON 发送 */
export function http(url, o = {}) {
    const opt = { timeout: 15000, ...o, headers: { ...(o.headers || {}) } };
    if (opt.body != null && typeof opt.body === 'object') {
        opt.body = JSON.stringify(opt.body);
        if (!header(opt.headers, 'content-type')) opt.headers['Content-Type'] = 'application/json';
    }
    if (opt.body != null && !opt.method) opt.method = 'post';
    return req(url, opt);
}

/** JSON.parse，但 16 位以上的整数（天翼/百度文件 id）转成字符串，避免精度丢失 */
export function parseJson(text) {
    return JSON.parse(String(text || '').replace(/([:\[,]\s*)(-?\d{16,})(?=\s*[,\]}])/g, '$1"$2"'));
}

export function getJson(url, o, name = '') {
    const r = http(url, o);
    try {
        return parseJson(r.content);
    } catch {
        throw new PanError(`${name}接口返回非 JSON: HTTP ${r.code}`);
    }
}

/** 响应头大小写不敏感读取（App 里保留服务端大小写，冒烟脚本里为小写） */
export function header(h, name) {
    name = name.toLowerCase();
    for (const k in h || {}) if (k.toLowerCase() === name) return String(h[k]);
    return '';
}

/** 多条 Set-Cookie 会被合并成 "a=1; Path=/, b=2; Expires=Wed, 21 Oct ..."，取出 {name: value} */
export function setCookies(h) {
    const out = {};
    for (const part of header(h, 'set-cookie').split(/,\s*(?=[^;=\s,]+=)/)) {
        const m = /^\s*([^=;\s]+)=([^;]*)/.exec(part);
        if (m) out[m[1]] = m[2];
    }
    return out;
}

export function cookieGet(cookie, name) {
    const m = new RegExp('(?:^|;\\s*)' + name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '=([^;]*)').exec(cookie || '');
    return m ? m[1] : '';
}

/** 替换或追加 cookie 中的一项 */
export function cookiePut(cookie, name, value) {
    const parts = (cookie || '').split(';').map(p => p.trim()).filter(p => p && !p.startsWith(name + '='));
    parts.push(`${name}=${value}`);
    return parts.join('; ');
}

/** 简易 cookie jar（不分域名，每个网盘一个）：手动跟随重定向并收集每一跳的 Set-Cookie */
export class Jar {
    constructor(cookie = '') {
        this.map = {};
        this.load(cookie);
    }
    load(cookie) {
        for (const p of (cookie || '').split(';')) {
            const i = p.indexOf('=');
            if (i > 0) this.map[p.slice(0, i).trim()] = p.slice(i + 1).trim();
        }
    }
    get size() { return Object.keys(this.map).length; }
    toString() { return Object.entries(this.map).map(([k, v]) => `${k}=${v}`).join('; '); }
    absorb(h) { Object.assign(this.map, setCookies(h)); }
    /** 带 cookie 请求并跟随重定向，返回最后一跳（附 url 字段） */
    fetch(url, o = {}) {
        let r;
        for (let i = 0; i < 10; i++) {
            const headers = { ...(o.headers || {}) };
            if (this.size) headers.Cookie = this.toString();
            r = http(url, { ...o, headers, redirect: 0 });
            this.absorb(r.headers);
            const loc = header(r.headers, 'location');
            if (!(r.code >= 300 && r.code < 400 && loc)) break;
            url = joinUrl(url, loc);
            o = { headers: o.headers, timeout: o.timeout };   // 重定向后改为 GET
        }
        r.url = url;
        return r;
    }
}

export const md5 = s => Crypto.MD5(s).toString();
export const sha1 = s => Crypto.SHA1(s).toString();
export const sha256 = s => Crypto.SHA256(s).toString();

/** base64（兼容 url-safe、缺 padding）→ UTF-8 文本 */
export function b64decode(s) {
    s = String(s || '').replace(/-/g, '+').replace(/_/g, '/').replace(/\s/g, '');
    return Crypto.enc.Base64.parse(s + '='.repeat((4 - s.length % 4) % 4)).toString(Crypto.enc.Utf8);
}
export const b64encode = s => Crypto.enc.Base64.stringify(Crypto.enc.Utf8.parse(s));

/** 16 字节随机数（CryptoJS 的 WordArray.random 依赖原生 crypto，JavaScriptCore 里没有） */
export function randomBytes(n) {
    const words = [];
    for (let i = 0; i < n; i += 4) words.push((Math.random() * 0x100000000) | 0);
    return Crypto.lib.WordArray.create(words, n);
}

/** 同步等待（JS 线程里的 req 本身也是阻塞的，转存轮询用） */
export function sleep(ms) {
    const end = Date.now() + ms;
    while (Date.now() < end) { /* ponytail: 忙等，接口轮询间隔才用 */ }
}
