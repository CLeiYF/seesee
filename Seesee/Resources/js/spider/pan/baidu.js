// 百度网盘（移植自 _pan/baidu.py ← api/BaiduDrive.kt + api/BaiDuYunHandler.kt）。
// 列分享匿名可用（verify 拿 randsk 再带 BDCLND 列目录）；播放需含 BDUSS 的 cookie（ext.baidu_cookie，jar 无此 ext，为本移植新增）。
import { CredentialError, PanError, cred, http, getJson, isMedia, queryPwd, qs, cookieGet, cookiePut, sha1, b64encode, b64decode, sleep } from './common.js';

const HOST = 'https://pan.baidu.com';
const HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 12; SM-X800) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/101.0.4951.40 Safari/537.36',
    Accept: 'application/json, text/plain, */*', 'Content-Type': 'application/x-www-form-urlencoded',
    Origin: 'https://pan.baidu.com', Referer: 'https://pan.baidu.com/' };
const APP_UA = 'netdisk;P2SP;2.2.91.136;android-android;';
const DLNA_UA = 'netdisk;1.4.2;22021211RC;android-android;12;JSbridge4.4.0;jointBridge;1.1.0;';
const DEVUID = '73CED981D0F186D12BC18CAE1684FFD5|VSRCQTF6W';
const SAVE_DIR = 'TVBOX_BD';
const COOKIE_KEY = 'baidu_cookie';

function fmt(size) {
    size = Number(size) || 0;
    if (size <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    let i = 0;
    while (size >= 1024 && i < 4) { size /= 1024; i++; }
    return size.toFixed(1) + ' ' + units[i];
}

class Baidu {
    NAME = '百度网盘';
    FLAG_PREFIX = 'BD';
    PATTERN = /https?:\/\/pan\.baidu\.com\/(?:s\/1([\w-]+)|share\/init\?surl=([\w-]+))/;
    uid = '';
    bdstoken = '';
    dirReady = false;

    reset() { this.uid = ''; this.bdstoken = ''; this.dirReady = false; }
    match(url) { return !!url && this.PATTERN.test(url); }
    ownsFlag(flag) { return (flag || '').startsWith(this.FLAG_PREFIX); }
    qualities() { return ['BD原画']; }
    get cookie() { return cred(COOKIE_KEY); }

    episodes(shareUrl) {
        const m = this.PATTERN.exec(shareUrl || '');
        if (!m) return [];
        const surl = m[1] || m[2], pwd = queryPwd(shareUrl);
        const v = getJson(`${HOST}/share/verify?t=${Date.now()}&surl=${surl}`, { method: 'post', headers: HEADERS,
            body: qs({ pwd, vcode: '', vcode_str: '' }) }, '百度');
        const randsk = v.randsk;
        if (!randsk) throw new PanError('百度分享不可用: errno=' + v.errno);
        const h = { ...HEADERS, Cookie: 'BDCLND=' + randsk };
        const out = [], seen = new Set(), pending = [{ shorturl: surl, root: '1' }];
        let uk = '', shareid = '';
        while (pending.length) {
            const q = pending.shift();
            for (let page = 1; ; page++) {
                const params = { ...q, page, num: 1000, desc: 0, order: 'name' };
                if (q.dir) Object.assign(params, { uk, shareid });
                const d = getJson(`${HOST}/share/list?` + qs(params), { headers: h }, '百度');
                const items = d.list || [];
                if (!q.dir && page === 1) {
                    uk = String(d.uk || ''); shareid = String(d.share_id || '');
                    if (!(uk && shareid)) throw new PanError('百度分享列表失败: errno=' + d.errno);
                }
                for (const it of items) {
                    if (Number(it.isdir) === 1) {
                        const path = it.path || `/sharelink${uk}-${it.fs_id}/${it.server_filename}`;
                        if (!seen.has(path) && seen.size < 500) { seen.add(path); pending.push({ dir: path }); }
                    } else if (isMedia(it.server_filename)) {
                        const data = { uk, shareid, fid: String(it.fs_id), randsk, surl, pname: it.server_filename, qtype: 'original' };
                        out.push([`[${fmt(it.size)}]${it.server_filename}`, b64encode(JSON.stringify(data))]);
                    }
                }
                if (items.length < 1000) break;
            }
        }
        return out;
    }

    // ---- 播放（需 BDUSS） ----
    ch() { return { ...HEADERS, Cookie: this.cookie }; }

    getUid() {
        if (!this.uid) {
            const j = getJson('https://mbd.baidu.com/userx/v1/info/get?appname=baiduboxapp&fields=%5B%22uid%22%5D'
                + '&client&clientfrom&lang=zh-cn&tpl&ttt', { headers: this.ch() }, '百度');
            this.uid = String(((j.data || {}).fields || {}).uid || '');
        }
        return this.uid;
    }

    /** BaiduDrive._getAppDownloadUrl */
    appDownload(v) {
        const t = String(Date.now());
        const bduss = cookieGet(this.cookie, 'BDUSS');
        const rand = sha1(sha1(bduss) + this.getUid() + 'ebrcUYiuxaZv2XGu7KIYKxUrqfnOfpDF' + t + DEVUID + '11.30.2ae5821440fab5e1a61a025f014bd8972');
        let sekey = v.randsk;
        try { sekey = decodeURIComponent(sekey); } catch { /* 原样 */ }
        const params = { shareid: v.shareid, uk: v.uk, fid: v.fid, sekey, origin: 'dlna', devuid: DEVUID, clienttype: '1',
            channel: 'android_12_zhao_bd-netdisk_1024266h', version: '11.30.2', time: t, rand };
        const j = getJson(`${HOST}/share/list?` + qs(params), { headers: { 'User-Agent': APP_UA, 'Accept-Language': 'zh-CN,zh;q=0.8',
            charset: 'UTF-8', cookie: this.cookie } }, '百度');
        return ((j.list || [])[0] || {}).dlink || '';
    }

    getBdstoken() {
        if (!this.bdstoken) {
            const j = getJson(`${HOST}/api/gettemplatevariable?clienttype=0&app_id=250528&web=1`
                + '&fields=["bdstoken","token","uk","isdocuser","servertime"]', { headers: this.ch() }, '百度');
            this.bdstoken = (j.result || {}).bdstoken || '';
        }
        return this.bdstoken;
    }

    /** BaiduDrive._getDownloadUrl：转存到 /TVBOX_BD 再取 dlink */
    transferDownload(v) {
        const cookie = cookiePut(this.cookie, 'BDCLND', v.randsk);
        const th = { 'User-Agent': 'Android', 'Content-Type': 'application/x-www-form-urlencoded', 'Accept-Language': 'zh-CN,zh;q=0.8',
            charset: 'UTF-8', Referer: HOST, Cookie: cookie };
        if (!this.dirReady) {
            const tok = this.getBdstoken();
            http(`${HOST}/api/filemanager?async=2&onnest=fail&opera=delete&bdstoken=${tok}&newVerify=1&clienttype=0&app_id=250528&web=1`,
                { method: 'post', headers: th, body: qs({ filelist: JSON.stringify(['/' + SAVE_DIR]) }) });
            http(`${HOST}/api/create?a=commit&bdstoken=${tok}&clienttype=0&app_id=250528&web=1`,
                { method: 'post', headers: this.ch(), body: qs({ path: '//' + SAVE_DIR, isdir: '1', block_list: '[]' }) });
            this.dirReady = true;
        }
        let to = '';
        for (let i = 0; i < 3 && !to; i++) {
            if (i) sleep(1000);
            const j = getJson(`${HOST}/share/transfer?` + qs({ from: v.uk, shareid: v.shareid, ondup: 'newcopy', path: '/' + SAVE_DIR,
                fsidlist: `[${v.fid}]` }), { method: 'post', body: '', headers: th }, '百度');
            to = (((j.extra || {}).list || [])[0] || {}).to || '';
        }
        if (!to) return '';
        const j = getJson(`${HOST}/api/mediainfo?` + qs({ type: 'M3U8_FLV_264_480', path: '/' + to, clienttype: '80', origin: 'dlna' }),
            { headers: { 'User-Agent': DLNA_UA, Cookie: cookie } }, '百度');
        return (j.info || {}).dlink || '';
    }

    play(playId) {
        if (!this.cookie || !this.cookie.includes('BDUSS')) throw new CredentialError(this.NAME, '含 BDUSS 的 cookie', COOKIE_KEY);
        const v = JSON.parse(b64decode(playId));
        let url = this.appDownload(v), ua = APP_UA;
        if (!url) { url = this.transferDownload(v); ua = DLNA_UA; }
        if (!url) throw new PanError(`百度获取播放地址失败（${COOKIE_KEY} 可能已失效）`);
        return { parse: 0, url, header: { 'User-Agent': ua } };
    }
}

export const baidu = new Baidu();
