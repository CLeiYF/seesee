// 移动云盘（移植自 _pan/yidong.py ← api/YunDrive.java + spider/YiDongYun.java）。
// 列分享与「极速」线路（转码 m3u8）匿名可用；「原画」需 Authorization Basic 串（ext.yun_cookie，jar 无此 ext，为本移植新增）。
import { Crypto } from 'assets://js/lib/cat.js';
import { CredentialError, PanError, cred, http, parseJson, b64decode, randomBytes, CHROME } from './common.js';

const BASE = 'https://share-kd-njs.yun.139.com/yun-share/richlifeApp/devapp/IOutLink/';
const KEY = Crypto.enc.Utf8.parse('PVGDwmcvfs1uV3d1');
const SKIP = /App|活动中心|免费|1T空间|免流/;
const COOKIE_KEY = 'yun_cookie';
const AES = { mode: Crypto.mode.CBC, padding: Crypto.pad.Pkcs7 };

function enc(text) {
    const iv = randomBytes(16);
    const ct = Crypto.AES.encrypt(Crypto.enc.Utf8.parse(text), KEY, { ...AES, iv }).ciphertext;
    return iv.clone().concat(ct).toString(Crypto.enc.Base64);
}

function dec(b64) {
    const raw = Crypto.enc.Base64.parse(String(b64 || '').trim());
    const iv = Crypto.lib.WordArray.create(raw.words.slice(0, 4), 16);
    const ct = Crypto.lib.WordArray.create(raw.words.slice(4), raw.sigBytes - 16);
    return Crypto.AES.decrypt({ ciphertext: ct }, KEY, { ...AES, iv }).toString(Crypto.enc.Utf8);
}

const BASE_HEADERS = { 'User-Agent': CHROME, 'Content-Type': 'application/json', 'hcy-cool-flag': '1',
    'x-deviceinfo': '||3|12.27.0|chrome|131.0.0.0|5c7c68368f048245e1ce47f1c0f8f2d0||windows 10|1536X695|zh-CN|||' };

class Yidong {
    NAME = '移动云盘';
    FLAG_PREFIX = '移动';
    PATTERN = /https?:\/\/(?:yun\.139\.com\/shareweb\/#\/w\/i\/|caiyun\.139\.com\/m\/i\?|caiyun\.139\.com\/w\/i\/)([\w-]+)/;
    cache = {};

    match(url) { return !!url && this.PATTERN.test(url); }
    ownsFlag(flag) { return (flag || '').startsWith('移动'); }
    qualities() { return ['移动(极速)', '移动(原画)']; }

    info(linkId, pca = 'root') {
        const key = linkId + '-' + pca;
        if (!this.cache[key]) {
            const body = { getOutLinkInfoReq: { account: '', linkID: linkId, passwd: '', caSrt: 1, coSrt: 1, srtDr: 0, bNum: 1,
                pCaID: pca, eNum: 200 }, commonAccountInfo: { account: '', accountType: 1 } };
            const r = http(BASE + 'getOutLinkInfoV6', { method: 'post', body: enc(JSON.stringify(body)), headers: BASE_HEADERS });
            let data;
            try { data = parseJson(dec(r.content)).data; } catch { /* 视为失效 */ }
            if (!data) throw new PanError('移动云盘分享已被取消，无法访问');
            this.cache[key] = data;
        }
        return this.cache[key];
    }

    /** playId = contentId++linkID++path：极速线路用 contentId，原画线路用 path */
    episodes(shareUrl) {
        const m = this.PATTERN.exec(shareUrl || '');
        if (!m) return [];
        const out = [];
        this.walk(m[1], 'root', out, 0);
        return out;
    }

    walk(linkId, pca, out, depth) {
        const d = this.info(linkId, pca);
        for (const co of d.coLst || []) {
            if (co.coType === 3) out.push([co.coName, [co.coID, linkId, co.path || ''].join('++')]);   // 视频
        }
        if (depth < 10) {
            for (const ca of d.caLst || []) if (!SKIP.test(ca.caName || '')) this.walk(linkId, ca.path, out, depth + 1);
        }
    }

    play(playId, flag) {
        const [cid, linkId, path] = (playId + '++++').split('++');
        if ((flag || '').includes('原画')) {
            const auth = cred(COOKIE_KEY);
            if (!auth) throw new CredentialError(this.NAME, 'Authorization', COOKIE_KEY);
            let phone;
            try { phone = b64decode(auth).split(':')[1]; } catch { /* 下面报错 */ }
            if (!phone) throw new PanError(`${COOKIE_KEY} 格式不对，应为 Authorization: Basic 后的 base64 串`);
            const body = { dlFromOutLinkReqV3: { linkID: linkId, account: phone, coIDLst: { item: [path || cid] } },
                commonAccountInfo: { account: phone, accountType: 1 } };
            const r = http(BASE + 'dlFromOutLinkV3', { method: 'post', body: enc(JSON.stringify(body)), headers: {
                'X-Deviceinfo': '||3|12.27.0|safari|13.1.2|1||macos 10.15.6|1324X381|zh-cn|||', 'hcy-cool-flag': '1',
                Authorization: 'Basic ' + auth, 'Content-Type': 'application/json' } });
            let j = {};
            try { j = parseJson(dec(r.content)); } catch { /* 下面报错 */ }
            if (!['0', 0].includes(j.resultCode) || !(j.data || {}).redrUrl) throw new PanError('移动云盘原画获取失败: ' + (j.desc || j.resultCode));
            return { parse: 0, url: j.data.redrUrl, header: { 'User-Agent': CHROME } };
        }
        // 极速：匿名接口拿转码 m3u8（Java fetchPlayUrl，无需登录）
        const r = http(BASE + 'getContentInfoFromOutLink', { headers: { 'User-Agent': CHROME },
            body: { getContentInfoFromOutLinkReq: { contentId: cid, linkID: linkId, account: '' }, commonAccountInfo: { account: '', accountType: 1 } } });
        const m3u8 = (((parseJson(r.content || '{}').data || {}).contentInfo) || {}).presentURL;
        if (!m3u8) throw new PanError('移动云盘播放地址获取失败');
        let url = m3u8;
        const line = (http(m3u8, {}).content || '').split('\n').find(l => l.includes('index.m3u8'));
        if (line) url = m3u8.split('playlist.m3u8')[0] + line.trim();
        return { parse: 0, url, header: { 'User-Agent': CHROME } };
    }
}

export const yidong = new Yidong();
