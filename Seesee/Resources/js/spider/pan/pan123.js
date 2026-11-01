// 123 云盘（移植自 _pan/pan123.py ← api/Pan123Api.kt + api/Pan123Handler.kt）。
// 列分享匿名可用；播放需 ext.pan_auth（token）或 ext.pan_passport + ext.pan_password（登录后 token 存 local）。jar 无此 ext，为本移植新增。
import { CredentialError, PanError, cred, setCred, http, parseJson, getSize, qs, b64decode } from './common.js';

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36';
const API = 'https://www.123684.com/b/api/share/';
const LOGIN = 'https://login.123pan.com/api/user/sign_in';
const AUTH_KEY = 'pan_auth', PASSPORT_KEY = 'pan_passport', PASSWORD_KEY = 'pan_password';

class Pan123 {
    NAME = '123云盘';
    FLAG_PREFIX = 'pan123';
    // Java 正则 + 不带 www 的 123pan.com/123pan.cn
    PATTERN = /https?:\/\/(?:www\.)?(?:123pan\.com|123pan\.cn|123592\.com|123912\.com|123865\.com|123684\.com)\/s\/([A-Za-z0-9_-]+)/;
    _auth = null;

    reset() { this._auth = null; }
    match(url) { return !!url && this.PATTERN.test(url); }
    ownsFlag(flag) { return (flag || '').startsWith(this.FLAG_PREFIX); }
    qualities() { return ['pan123原画']; }

    /** Pan123Api.getShareData：key + 提取码 */
    shareData(url) {
        let u = url || '';
        try { u = decodeURIComponent(u); } catch { /* 原样 */ }
        u = u.replace(/：/g, ':');
        const m = this.PATTERN.exec(u);
        if (!m) return ['', ''];
        const pwd = /(?:pwd=|提取码:?\s*)([A-Za-z0-9]+)/.exec(u);
        return [m[1].replace('.html', ''), pwd ? pwd[1] : ''];
    }

    episodes(shareUrl) {
        const [key, pwd] = this.shareData(shareUrl);
        if (!key) return [];
        const out = [];
        this.list(key, pwd, 0, out, 0);
        return out;
    }

    list(key, pwd, parent, out, depth) {
        const dirs = [];
        let next = 0;
        for (let page = 1; ; page++) {
            const r = http(API + 'get?' + qs({ limit: 100, next, orderBy: 'file_name', orderDirection: 'asc', shareKey: key,
                SharePwd: pwd, ParentFileId: parent, Page: page }), { headers: { 'User-Agent': UA } });
            const j = parseJson(r.content || '{}');
            if (j.code !== 0) {
                if (parent === 0) throw new PanError('123分享不可用: ' + j.message);
                return;
            }
            const d = j.data || {}, items = d.InfoList || [];
            for (const it of items) {
                if (it.Type === 1) dirs.push(it.FileId);
                else if (it.Category === 2) {   // 视频
                    out.push([`[${getSize(it.Size)}]${it.FileName}`, [key, it.FileId, it.S3KeyFlag || '', it.Size || 0, it.Etag || ''].join('++')]);
                }
            }
            next = d.Next ?? -1;
            if (String(next) === '-1' || !items.length) break;
        }
        if (depth < 10) for (const sub of dirs) this.list(key, pwd, sub, out, depth + 1);
    }

    // ---- 登录 ----
    auth() {
        if (this._auth === null) {
            this._auth = cred(AUTH_KEY);
            if (this._auth && expired(this._auth)) this._auth = '';
            if (!this._auth) this._auth = this.login();
        }
        if (!this._auth) {
            this._auth = null;
            throw new CredentialError(this.NAME, 'token 或账号密码', AUTH_KEY, `${PASSPORT_KEY} + ext.${PASSWORD_KEY}`);
        }
        return this._auth;
    }

    /** Pan123Api.login：账号密码换 token 并写回 */
    login() {
        const user = cred(PASSPORT_KEY), pwd = cred(PASSWORD_KEY);
        if (!(user && pwd)) return '';
        const r = http(LOGIN, { body: { passport: user, password: pwd, remember: true }, headers: {
            'User-Agent': UA, 'App-Version': '43', Origin: 'https://login.123pan.com',
            Referer: 'https://login.123pan.com/centerlogin?redirect_url=https%3A%2F%2Fwww.123684.com&source_page=website' } });
        const token = ((r.code === 200 ? parseJson(r.content) : {}).data || {}).token;
        if (!token) throw new PanError('123登录失败: HTTP ' + r.code);
        setCred(AUTH_KEY, token);
        return token;
    }

    play(playId) {
        const auth = this.auth();
        const [key, fid, s3, size, etag] = (playId + '++++++++').split('++');
        const r = http(API + 'download/info', { headers: { 'User-Agent': UA, Authorization: 'Bearer ' + auth, platform: 'android' },
            body: { ShareKey: key, FileID: Number(fid), S3KeyFlag: s3, Size: Number(size || 0), Etag: etag } });
        const j = r.code === 200 ? parseJson(r.content) : {};
        const enc = (j.data || {}).DownloadURL;
        if (!enc) {
            if (j.code === 401) { setCred(AUTH_KEY, ''); this._auth = null; }
            throw new PanError('123获取下载链接失败: ' + (j.message || r.code));
        }
        const p = /[?&]params=([^&]+)/.exec(enc);
        const url = p ? b64decode(decodeURIComponent(p[1])) : enc;
        return { parse: 0, url, header: { 'User-Agent': UA } };
    }
}

function expired(token) {
    try {
        const exp = JSON.parse(b64decode(token.split('.')[1])).exp || 0;
        return !!exp && exp < Date.now() / 1000 + 60;
    } catch {
        return false;
    }
}

export const pan123 = new Pan123();
