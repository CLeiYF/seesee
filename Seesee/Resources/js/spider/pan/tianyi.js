// 天翼云盘（移植自 _pan/tianyi.py ← api/TianyiApi.java + api/TianYiHandler.java）。
// 列分享匿名可用；播放需登录：Cloud 类站点 ext.tianyicookie / TianYi.js 的 ext，为 cookie 串或 {"username","password"}（同 TianyiApi.setCookie）。
import { Crypto } from 'assets://js/lib/cat.js';
import { CredentialError, PanError, Jar, cred, setCred, getJson, getSize, queryPwd, qs, CHROME } from './common.js';

const LOGIN_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:74.0) Gecko/20100101 Firefox/76.0';
const OPEN = 'https://open.e.189.cn';
const API = 'https://cloud.189.cn/api/open/share/';
const LOGIN_URL = 'https://cloud.189.cn/api/portal/loginUrl.action?redirectURL=https://cloud.189.cn/web/redirect.html?returnURL=/main.action';
const REFRESH_URL = 'https://cloud.189.cn/api/portal/loginUrl.action?redirectURL=https%3A%2F%2Fcloud.189.cn%2Fweb%2F'
    + 'redirect.html&defaultSaveName=3&defaultSaveNameCheck=uncheck&browserId=16322f24d9405fb83331c3f6ce971b53';
const COOKIE_KEY = 'cloud_cookie', ACCOUNT_KEY = 'cloud_account', PASSWORD_KEY = 'cloud_password';

class Tianyi {
    NAME = '天翼云盘';
    FLAG_PREFIX = '天意';   // 沿用 Java 的线路名
    PATTERN = /https?:\/\/cloud\.189\.cn\/(?:t\/|web\/share\?code=)([A-Za-z0-9]+)/;
    jar = null;
    sessionKey = '';

    reset() { this.jar = null; this.sessionKey = ''; }
    match(url) { return !!url && this.PATTERN.test(url); }
    ownsFlag(flag) { return (flag || '').startsWith(this.FLAG_PREFIX); }
    qualities() { return ['天意']; }

    get(url, params) {
        const h = { accept: 'application/json;charset=UTF-8', 'User-Agent': CHROME };
        if (this.sessionKey) h.sessionKey = this.sessionKey;
        if (this.jar && this.jar.size) h.Cookie = this.jar.toString();
        return getJson(url + (params ? '?' + qs(params) : ''), { headers: h }, '天翼');
    }

    // ---- 分享（匿名） ----
    episodes(shareUrl) {
        const m = this.PATTERN.exec(shareUrl || '');
        if (!m) return [];
        const code = m[1], pwd = queryPwd(shareUrl);
        if (pwd) this.get(API + 'checkAccessCode.action', { shareCode: code, accessCode: pwd });
        const info = this.get(API + 'getShareInfoByCodeV2.action', { noCache: '0.8886566349412803', shareCode: code });
        if (info.res_code !== 0) throw new PanError('天翼分享不可用: ' + (info.res_message || info.res_code));
        if (info.isFolder === false) {
            return [[(info.fileName + ' ' + getSize(info.fileSize)).trim(), `${info.fileId}++${info.shareId}`]];
        }
        const share = { shareId: info.shareId, shareMode: info.shareMode ?? 1, isFolder: String(info.isFolder ?? true).toLowerCase(), accessCode: pwd };
        const out = [];
        this.list(share, String(info.fileId), out, 0);
        return out;
    }

    list(share, folder, out, depth) {
        const dirs = [];
        for (let page = 1; ; page++) {
            const d = this.get(API + 'listShareDir.action', {
                pageNum: page, pageSize: 200, fileId: folder, shareDirFileId: folder, isFolder: share.isFolder,
                shareId: share.shareId, shareMode: share.shareMode, iconOption: 5, orderBy: 'filename',
                descending: 'false', accessCode: share.accessCode });
            if (d.res_code !== 0) break;
            const ao = d.fileListAO || {}, files = ao.fileList || [], folders = ao.folderList || [];
            for (const f of files) {
                if (f.mediaType === 3 && (f.size || 0) >= 5 * 1024 * 1024) {
                    out.push([(f.name + ' ' + getSize(f.size)).trim(), `${f.id}++${share.shareId}`]);
                }
            }
            dirs.push(...folders.map(x => String(x.id)));
            if (!(files.length || folders.length) || (ao.count || 0) <= page * 200) break;
        }
        if (depth < 10) for (const sub of dirs) this.list(share, sub, out, depth + 1);
    }

    // ---- 登录 / cookie ----
    saveCookie() { setCred(COOKIE_KEY, this.jar.toString()); }

    /** TianYiHandler.loginWithPassword */
    login() {
        const user = cred(ACCOUNT_KEY), pwd = cred(PASSWORD_KEY);
        if (!(user && pwd)) return false;
        const pub = this.jar.fetch(OPEN + '/api/logbox/config/encryptConf.do?appId=cloud', { method: 'post', body: '' });
        const pubKey = JSON.parse(pub.content).data.pubKey;
        const r = this.jar.fetch(LOGIN_URL, { headers: { 'User-Agent': CHROME } });
        const lt = /[?&]lt=(\w+)/.exec(r.url), reqId = /[?&]reqId=(\w+)/.exec(r.url);
        if (!(lt && reqId)) throw new PanError('天翼登录失败: 未获取到 lt/reqId');
        const h = { 'Content-Type': 'application/x-www-form-urlencoded', 'User-Agent': LOGIN_UA, Referer: OPEN + '/', Lt: lt[1], Reqid: reqId[1] };
        const conf = JSON.parse(this.jar.fetch(OPEN + '/api/logbox/oauth2/appConf.do', { method: 'post', headers: h,
            body: qs({ version: '2.0', appKey: 'cloud' }) }).content).data;
        const pem = '-----BEGIN PUBLIC KEY-----\n' + pubKey + '\n-----END PUBLIC KEY-----';
        // rsaX 输出 base64，接口要 hex
        const enc = t => '{NRP}' + b64ToHex(rsaX('RSA/PKCS1', true, true, t, false, pem, true));
        const res = JSON.parse(this.jar.fetch(OPEN + '/api/logbox/oauth2/loginSubmit.do', { method: 'post', headers: h, body: qs({
            appKey: 'cloud', version: '2.0', accountType: '02', validateCode: '', returnUrl: conf.returnUrl,
            paramId: conf.paramId, captchaToken: '', dynamicCheck: 'FALSE', clientType: '1', cb_SaveName: '3',
            isOauth2: 'false', userName: enc(user), password: enc(pwd) }) }).content || '{}');
        if (!res.toUrl) throw new PanError('天翼登录失败: ' + (res.msg || ''));
        this.jar.fetch(res.toUrl, { headers: { 'User-Agent': CHROME } });
        this.saveCookie();
        return true;
    }

    /** TianYiHandler.refreshCookie：凭 SSON 走一遍登录重定向拿新会话；失败再用账号密码登录 */
    refreshCookie() {
        this.jar.fetch(REFRESH_URL, { headers: { 'User-Agent': CHROME } });
        this.sessionKey = '';
        if (this.getSessionKey()) {
            this.saveCookie();
            return true;
        }
        return this.login();
    }

    getSessionKey() {
        if (!this.sessionKey) this.sessionKey = this.get('https://cloud.189.cn/api/portal/v2/getUserBriefInfo.action').sessionKey || '';
        return this.sessionKey;
    }

    ensureLogin() {
        if (!this.jar) this.jar = new Jar(cred(COOKIE_KEY));
        if (!this.jar.size && !this.login()) throw new CredentialError(this.NAME, 'cookie 或账号密码', 'tianyicookie');
        if (!this.getSessionKey() && !this.refreshCookie()) throw new PanError(`天翼登录已失效，请更新配置 ext.tianyicookie`);
    }

    play(playId) {
        this.ensureLogin();
        const [fileId, shareId] = (playId + '++').split('++');
        for (let attempt = 0; attempt < 2; attempt++) {
            const d = this.get('https://cloud.189.cn/api/portal/getNewVlcVideoPlayUrl.action',
                { shareId, dt: 1, fileId, type: 4, key: 'noCache' });
            if (d.res_code === 0 && (d.normal || {}).url) {
                return { parse: 0, url: d.normal.url, header: { 'User-Agent': CHROME, Cookie: this.jar.toString() } };
            }
            if (d.errorCode === 'InvalidSessionKey' && attempt === 0) {
                this.refreshCookie();
                continue;
            }
            throw new PanError('天翼获取播放地址失败: ' + (d.res_message || d.errorCode));
        }
    }
}

const b64ToHex = b64 => Crypto.enc.Base64.parse(b64).toString(Crypto.enc.Hex);

export const tianyi = new Tianyi();
