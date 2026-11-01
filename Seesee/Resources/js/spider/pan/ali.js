// 阿里云盘（移植自 _pan/ali.py ← api/AliYun.java）。不含 Android 本地代理：原画返回直链，普画返回多清晰度 m3u8 列表。
// 列分享匿名可用；播放需 refresh_token（Cloud 类站点 ext.token，Ali.js 的 ext 本身即 token，可为返回 token 的 URL）；开放平台 token 自动换取存 local。
import { CredentialError, PanError, cred, setCred, http, parseJson, getSize, queryPwd } from './common.js';

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36';
const API = 'https://api.aliyundrive.com/';
const OPEN = 'https://open.aliyundrive.com/adrive/v1.0/';
const ALIST = 'https://api.xhofe.top/alist/ali_open/';
const CANARY = 'client=Android,app=adrive,version=v4.3.1';
const TOKEN_KEY = 'ali_token', OPEN_KEY = 'ali_open_token';
const LINES = ['轉存原畫', '分享原畫', '代理普畫'];

const h = extra => ({ 'User-Agent': UA, Referer: 'https://www.aliyundrive.com/', 'Content-Type': 'application/json', ...extra });
const post = (url, body, headers) => {
    const r = http(url, { body, headers });
    let j = {};
    try { j = parseJson(r.content || '{}'); } catch { /* 空 */ }
    return { code: r.code, j };
};
const qualityOf = flag => (flag || '').split('#')[0];

class Ali {
    NAME = '阿里云盘';
    FLAG_PREFIX = '阿里';
    PATTERN = /https?:\/\/(?:www\.)?(?:aliyundrive|alipan)\.com\/s\/([A-Za-z0-9]+)(?:\/folder\/([A-Za-z0-9]+))?/;
    share = {};       // share_id -> [token, 过期时间]
    access = '';
    driveId = '';
    openAccess = '';

    reset() { this.access = ''; this.driveId = ''; this.openAccess = ''; }
    match(url) { return !!url && this.PATTERN.test(url); }
    ownsFlag(flag) { const q = qualityOf(flag); return q.startsWith(this.FLAG_PREFIX) || LINES.includes(q); }
    qualities() { return LINES.map(x => this.FLAG_PREFIX + x); }

    shareToken(sid, pwd = '') {
        const [tok, exp] = this.share[sid] || ['', 0];
        if (tok && exp > Date.now()) return tok;
        const { j } = post(API + 'v2/share_link/get_share_token', { share_id: sid, share_pwd: pwd }, h());
        if (!j.share_token) throw new PanError('阿里分享不可用: ' + (j.code || j.message));
        this.share[sid] = [j.share_token, Date.now() + ((Number(j.expires_in) || 7200) - 60) * 1000];
        return j.share_token;
    }

    // ---- 分享列表（匿名） ----
    episodes(shareUrl) {
        const m = this.PATTERN.exec(shareUrl || '');
        if (!m) return [];
        const sid = m[1];
        let folder = m[2] || '';
        const tok = this.shareToken(sid, queryPwd(shareUrl));
        if (!folder) {
            const { j } = post(API + 'adrive/v3/share_link/get_share_by_anonymous', { share_id: sid }, h());
            const first = (j.file_infos || [{}])[0] || {};
            folder = first.type === 'folder' ? first.file_id : 'root';
        }
        const out = [];
        this.list(sid, tok, folder, '', out, 0);
        return out;
    }

    list(sid, tok, parent, parentName, out, depth) {
        const dirs = [];
        let marker = '';
        do {
            const body = { limit: 200, share_id: sid, parent_file_id: parent, order_by: 'name', order_direction: 'ASC' };
            if (marker) body.marker = marker;
            const { j } = post(API + 'adrive/v3/file/list', body, h({ 'x-share-token': tok, 'X-Canary': CANARY }));
            for (const it of j.items || []) {
                if (it.type === 'folder') dirs.push([it.file_id, it.name || '']);
                else if (it.category === 'video' || it.category === 'audio') {
                    const name = [parentName ? `[${parentName}]` : '', it.name || '', it.size ? `[${getSize(it.size)}]` : ''].filter(Boolean).join(' ');
                    out.push([name, `${sid}+${it.file_id}`]);
                }
            }
            marker = j.next_marker || '';
        } while (marker);
        if (depth < 10) for (const [fid, name] of dirs) this.list(sid, tok, fid, name, out, depth + 1);
    }

    // ---- 登录态 ----
    /** AliYun.refreshAccessToken：refresh_token 换 access_token，新 refresh_token 写回 */
    refreshAccess() {
        const saved = cred(TOKEN_KEY);
        if (!saved) throw new CredentialError(this.NAME, 'refresh_token', 'token');
        const rt = saved.startsWith('http') ? http(saved, {}).content.trim() : saved;
        const { j } = post('https://auth.aliyundrive.com/v2/account/token', { refresh_token: rt, grant_type: 'refresh_token' }, h());
        if (!j.access_token) throw new PanError(`阿里 token 刷新失败，请更新配置 ext.token: ${j.code || ''}`);
        this.access = `${j.token_type || 'Bearer'} ${j.access_token}`;
        this.driveId = j.resource_drive_id || j.default_drive_id || '';
        if (j.refresh_token && j.refresh_token !== rt && !saved.startsWith('http')) setCred(TOKEN_KEY, j.refresh_token);
    }

    auth(path, body, sid, retry = true) {
        if (!this.access) this.refreshAccess();
        const url = path.startsWith('http') ? path : API + path;
        const r = post(url, body, h({ 'x-share-token': this.shareToken(sid), 'X-Canary': CANARY, authorization: this.access }));
        if (r.code === 401 && retry) {
            this.access = '';
            return this.auth(path, body, sid, false);
        }
        return r.j;
    }

    getDriveId(sid) {
        if (!this.driveId) {
            const j = this.auth('https://user.aliyundrive.com/v2/user/get', {}, sid);
            this.driveId = j.resource_drive_id || j.default_drive_id || '';
        }
        return this.driveId;
    }

    /** AliYun.refreshOpenToken / oauthRequest：经 alist 换开放平台 token */
    openToken(sid) {
        if (this.openAccess) return this.openAccess;
        const rt = cred(OPEN_KEY);
        let j;
        if (rt) {
            j = post(ALIST + 'token', { grant_type: 'refresh_token', refresh_token: rt }, h()).j;
        } else {
            const code = this.auth('https://open.aliyundrive.com/oauth/users/authorize?client_id=76917ccccd4441c39457a04f6084fb2f'
                + '&redirect_uri=https://alist.nn.ci/tool/aliyundrive/callback&scope=user:base,file:all:read,file:all:write&state=',
            { authorize: 1, scope: 'user:base,file:all:read,file:all:write' }, sid);
            const m = /code=(\w+)/.exec(code.redirectUri || '');
            if (!m) throw new PanError('阿里开放平台授权失败');
            j = post(ALIST + 'code', { code: m[1], grant_type: 'authorization_code' }, h()).j;
        }
        if (!j.access_token) throw new PanError('阿里开放平台 token 获取失败: ' + (j.message || j.code));
        this.openAccess = `${j.token_type || 'Bearer'} ${j.access_token}`;
        if (j.refresh_token) setCred(OPEN_KEY, j.refresh_token);
        return this.openAccess;
    }

    oauth(path, body, sid) {
        return post(OPEN + path, body, h({ authorization: this.openToken(sid) })).j;
    }

    copy(sid, fid) {
        const j = this.auth('adrive/v2/batch', { requests: [{ body: { file_id: fid, share_id: sid, auto_rename: true,
            to_parent_file_id: 'root', to_drive_id: this.getDriveId(sid) }, headers: { 'Content-Type': 'application/json' },
        id: '0', method: 'POST', url: '/file/copy' }], resource: 'file' }, sid);
        const id = (((j.responses || [{}])[0] || {}).body || {}).file_id;
        if (!id) throw new PanError('阿里转存失败');
        return id;
    }

    remove(sid, fid) {
        try {
            this.auth('adrive/v2/batch', { requests: [{ body: { drive_id: this.driveId, file_id: fid },
                headers: { 'Content-Type': 'application/json' }, id: fid, method: 'POST', url: '/file/delete' }], resource: 'file' }, sid);
        } catch { /* 忽略 */ }
    }

    play(playId, flag) {
        if (!cred(TOKEN_KEY)) throw new CredentialError(this.NAME, 'refresh_token', 'token');
        const [sid, fid] = (playId + '+').split('+');
        const line = qualityOf(flag);
        const header = { 'User-Agent': UA, Referer: 'https://www.aliyundrive.com/' };
        if (line.endsWith('分享原畫')) {
            const j = this.auth('v2/file/get_share_link_download_url', { file_id: fid, share_id: sid, expire_sec: 600 }, sid);
            if (!j.download_url) throw new PanError('阿里分享下载地址获取失败: ' + j.code);
            return { parse: 0, url: j.download_url, header };
        }
        const tmp = this.copy(sid, fid);
        try {
            if (line.endsWith('代理普畫')) {
                const j = this.oauth('openFile/getVideoPreviewPlayInfo', { file_id: tmp, drive_id: this.driveId,
                    category: 'live_transcoding', url_expire_sec: 900 }, sid);
                const tasks = ((j.video_preview_play_info || {}).live_transcoding_task_list) || [];
                const urls = [];
                for (const t of tasks.slice().reverse()) if (t.url) urls.push(t.template_id || '', t.url);   // 高清在前
                if (!urls.length) throw new PanError('阿里转码地址获取失败');
                return { parse: 0, url: urls, header };
            }
            const j = this.oauth('openFile/getDownloadUrl', { file_id: tmp, drive_id: this.driveId, expire_sec: 900 }, sid);
            if (!j.url) throw new PanError('阿里下载地址获取失败: ' + j.code);
            return { parse: 0, url: j.url, header };
        } finally {
            this.remove(sid, tmp);
        }
    }
}

export const ali = new Ali();
