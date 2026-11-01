// 夸克网盘（移植自 _pan/quark.py ← AndroidCatVodSpider api/QuarkApi.java）。UC 与它同一套 clouddrive 接口，见 uc.js。
// 列分享匿名可用；播放需转存到自己网盘，必须有 cookie（Cloud 类站点 ext.cookie，Quark.js 的 ext 本身即 cookie）。
import { CredentialError, PanError, cred, setCred, http, parseJson, getSize, isMedia, queryPwd, setCookies, cookieGet, cookiePut, sleep } from './common.js';

export class QuarkLike {
    constructor(c) {
        Object.assign(this, { SAVE_DIR: 'TV', QUALITY_LABELS: ['4K', '超清', '高清', '普画'],
            QUALITY_CODES: ['4k', '2k', 'super', 'high', 'normal', 'low'] }, c);
        this._cookie = null;
        this._vip = null;
        this.shareTokens = {};
        this.saveIds = {};
        this.saveDirId = null;
    }

    reset() { this._cookie = null; this._vip = null; this._access = null; }
    match(url) { return !!url && this.PATTERN.test(url); }
    ownsFlag(flag) { return (flag || '').startsWith(this.FLAG_PREFIX); }
    static qualityOf(flag) { return (flag || '').split('#')[0]; }

    get cookie() {
        if (this._cookie === null) this._cookie = cred(this.COOKIE_KEY);
        return this._cookie;
    }

    needCookie() {
        if (!this.cookie) throw new CredentialError(this.NAME, 'cookie', this.EXT_KEY);
    }

    headers(json) {
        const h = { 'User-Agent': this.UA, Referer: this.REFERER };
        if (json) h['Content-Type'] = 'application/json';
        if (this.cookie) h.Cookie = this.cookie;
        return h;
    }

    api(path, data, method = 'GET') {
        const url = this.API + path;
        const o = method === 'GET' ? { headers: this.headers(false) } : { body: data || {}, headers: this.headers(true) };
        const r = http(url, o);
        let json;
        try { json = parseJson(r.content); } catch { throw new PanError(`${this.NAME} 接口返回非 JSON: HTTP ${r.code}`); }
        // 同 Java：Set-Cookie 里有新的 __puus 就刷新 cookie 并写回
        const puus = setCookies(r.headers).__puus;
        if (puus && this.cookie && cookieGet(this.cookie, '__puus') !== puus) {
            this._cookie = cookiePut(this.cookie, '__puus', puus);
            setCred(this.COOKIE_KEY, this._cookie);
        }
        return json;
    }

    isVip() {
        if (this._vip === null) {
            this._vip = false;
            if (this.cookie) {
                try {
                    const d = this.api('member?pr=ucpro&fr=pc&uc_param_str=&fetch_subscribe=true&_ch=home&fetch_identity=true');
                    this._vip = String((d.data || {}).member_type || '').includes('VIP');
                } catch { /* 当普通用户 */ }
            }
        }
        return this._vip;
    }

    qualities() {
        const labels = this.isVip() ? this.QUALITY_LABELS : ['普画'];
        return [this.FLAG_PREFIX + '原画', ...labels.map(q => this.FLAG_PREFIX + q)];
    }

    // ---- 分享 ----
    shareToken(sid, pwd) {
        if (!this.shareTokens[sid]) {
            const d = this.api('share/sharepage/token?' + this.PR, { pwd_id: sid, passcode: pwd || '' }, 'POST');
            const st = (d.data || {}).stoken;
            if (!st) throw new PanError(`${this.NAME} 分享不可用: ${d.message || d.code}`);
            this.shareTokens[sid] = st;
        }
        return this.shareTokens[sid];
    }

    episodes(shareUrl) {
        const m = this.PATTERN.exec(shareUrl || '');
        if (!m) return [];
        const sid = m[1];
        const stoken = this.shareToken(sid, queryPwd(shareUrl));
        const out = [];
        this.list(sid, stoken, '0', out, 0);
        return out;
    }

    list(sid, stoken, fid, out, depth) {
        const size = 200, dirs = [];
        for (let page = 1; ; page++) {
            const d = this.api(`share/sharepage/detail?${this.PR}&pwd_id=${sid}&stoken=${encodeURIComponent(stoken)}&pdir_fid=${fid}`
                + `&force=0&_page=${page}&_size=${size}&_sort=file_type:asc,file_name:asc`);
            const items = (d.data || {}).list || [];
            for (const it of items) {
                if (it.dir) dirs.push(it.fid);
                else if (it.file && isMedia(it.file_name)) {
                    if ((it.size || 0) < 5 * 1024 * 1024) continue;
                    out.push([(it.file_name + ' ' + getSize(it.size)).trim(),
                        [it.fid, it.share_fid_token || '', sid, stoken].join('++')]);
                }
            }
            const total = (d.metadata || {})._total || 0;
            if (!items.length || page * size >= total) break;
        }
        if (depth < 10) for (const sub of dirs) this.list(sid, stoken, sub, out, depth + 1);
    }

    // ---- 转存 ----
    createSaveDir() {
        if (this.saveDirId) return this.clearSaveDir();
        const d = this.api(`file/sort?${this.PR}&pdir_fid=0&_page=1&_size=200&_sort=file_type:asc,updated_at:desc`);
        const dir = ((d.data || {}).list || []).find(it => it.file_name === this.SAVE_DIR);
        if (dir) {
            this.saveDirId = dir.fid;
            this.clearSaveDir();
        } else {
            const c = this.api('file?' + this.PR, { pdir_fid: '0', file_name: this.SAVE_DIR, dir_path: '', dir_init_lock: false }, 'POST');
            this.saveDirId = (c.data || {}).fid;
        }
        if (!this.saveDirId) throw new PanError(`${this.NAME} 创建转存目录失败（cookie 可能已失效，ext.${this.EXT_KEY}）`);
    }

    clearSaveDir() {
        const d = this.api(`file/sort?${this.PR}&pdir_fid=${this.saveDirId}&_page=1&_size=200&_sort=file_type:asc,updated_at:desc`);
        const files = (d.data || {}).list || [];
        if (files.length >= 10) {
            this.api(`file/delete?${this.PR}&uc_param_str=`, { action_type: 2, filelist: files.map(f => f.fid), exclude_fids: [] }, 'POST');
        }
    }

    save(fid, ftoken, sid, stoken) {
        if (this.saveIds[fid]) return this.saveIds[fid];
        this.createSaveDir();
        this.saveIds = {};
        const d = this.api('share/sharepage/save?' + this.PR, {
            fid_list: [fid], fid_token_list: [ftoken], to_pdir_fid: this.saveDirId,
            pwd_id: sid, stoken, pdir_fid: '0', scene: 'link' }, 'POST');
        const task = (d.data || {}).task_id;
        if (!task) throw new PanError(`${this.NAME} 转存失败: ${d.message}`);
        for (let retry = 0; retry < 3; retry++) {
            const t = this.api(`task?${this.PR}&task_id=${task}&retry_index=${retry}`);
            const top = (((t.data || {}).save_as || {}).save_as_top_fids) || [];
            if (top.length) return (this.saveIds[fid] = top[0]);
            sleep(1000);
        }
        throw new PanError(`${this.NAME} 转存任务超时`);
    }

    downloadUrl(saveFid) {
        const d = this.api(`file/download?${this.PR}&uc_param_str=`, { fids: [saveFid] }, 'POST');
        const url = ((d.data || [])[0] || {}).download_url;
        if (!url) throw new PanError(`${this.NAME} 获取下载地址失败: ${d.message}`);
        return url;
    }

    transcodingUrl(saveFid, flag) {
        const d = this.api('file/v2/play?' + this.PR, { fid: saveFid, resolutions: 'normal,low,high,super,2k,4k', supports: 'fmp4' }, 'POST');
        const videos = ((d.data || {}).video_list || []).filter(v => (v.video_info || {}).url);
        if (!videos.length) throw new PanError(`${this.NAME} 获取转码地址失败: ${d.message}`);
        const label = QuarkLike.qualityOf(flag).slice(this.FLAG_PREFIX.length);
        const vip = this.isVip();
        const i = this.QUALITY_LABELS.indexOf(label);
        const want = vip && i >= 0 ? this.QUALITY_CODES[i] : (vip ? this.QUALITY_CODES[0] : 'low');
        return (videos.find(v => v.resolution === want) || videos[0]).video_info.url;
    }

    play(playId, flag) {
        this.needCookie();
        const [fid, ftoken, sid, stoken] = (playId + '++++++').split('++');
        const saveFid = this.save(fid, ftoken, sid, stoken);
        const url = QuarkLike.qualityOf(flag).includes('原画') ? this.downloadUrl(saveFid) : this.transcodingUrl(saveFid, flag);
        return { parse: 0, url, header: this.headers(false) };
    }
}

export const quark = new QuarkLike({
    NAME: '夸克网盘',
    FLAG_PREFIX: 'quark',
    PATTERN: /https?:\/\/pan\.quark\.cn\/s\/([^\\|#/?&\s"]+)/,
    API: 'https://drive-pc.quark.cn/1/clouddrive/',
    PR: 'pr=ucpro&fr=pc',
    REFERER: 'https://pan.quark.cn/',
    UA: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) quark-cloud-drive/2.5.20 '
        + 'Chrome/100.0.4896.160 Electron/18.3.5.4-b478491100 Safari/537.36 Channel/pckk_other_ch',
    COOKIE_KEY: 'quark_cookie',
    EXT_KEY: 'cookie',
    QUALITY_LABELS: ['4K'],   // Java：VIP 只开放 4K 线路
});
