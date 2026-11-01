// UC 网盘（移植自 _pan/uc.py ← api/UCApi.java + api/UCTokenHandler.java）。与夸克同一套接口。
// 播放需 cookie（Cloud 类站点 ext.uccookie，UC.js 的 ext 本身即 cookie）；可选 TV 接口 refresh_token（ext.uc_token_cookie），有它时原画走 TV 接口。
import { QuarkLike } from './quark.js';
import { PanError, cred, setCred, http, parseJson, qs, md5, sha256 } from './common.js';

const TV_UA = 'Mozilla/5.0 (Linux; U; Android 13; zh-cn; M2004J7AC Build/UKQ1.231108.001) AppleWebKit/533.1 '
    + '(KHTML, like Gecko) Mobile Safari/533.1';
const CLIENT_ID = '5acf882d27b74502b7040b0c65519aa7';
const SIGN_KEY = 'l3srvtd7p42l0d0x1u8d7yc8ye9kki4d';
const OPEN_API = 'https://open-api-drive.uc.cn';
const CODE_API = 'http://api.extscreen.com/ucdrive';
const DEVICE_ID = '07b48aaba8a739356ab8107b5e230ad4';
const TOKEN_KEY = 'uc_token_cookie';

function device() {
    const ts = String(Math.floor(Date.now() / 1000) + 1) + '000';
    return { ts, req: md5(DEVICE_ID + ts).slice(0, 16) };
}

const deviceParams = () => ({
    app_ver: '1.6.8', device_brand: 'Xiaomi', platform: 'tv', device_name: 'M2004J7AC', device_model: 'M2004J7AC',
    build_device: 'M2004J7AC', build_product: 'M2004J7AC', device_gpu: 'Adreno (TM) 550', activity_rect: '%7B%7D',
    channel: 'UCTVOFFICIALWEB',
});

class UC extends QuarkLike {
    constructor() {
        super({
            NAME: 'UC网盘',
            FLAG_PREFIX: 'uc',
            PATTERN: /https?:\/\/(?:drive|fast)\.uc\.cn\/s\/([^\\|#/?&\s"]+)/,
            API: 'https://pc-api.uc.cn/1/clouddrive/',
            PR: 'pr=UCBrowser&fr=pc&sys=darwin&ve=1.8.6&ut=Nk27FcCv6q1eo6rXz8QHR/nIG6qLA3jh7KdL+agFgcOvww==',
            REFERER: 'https://drive.uc.cn',
            UA: 'Mozilla/5.0 (Linux; Android 8.0.0; SM-G955U Build/R16NW) AppleWebKit/537.36 (KHTML, like Gecko) '
                + 'Chrome/116.0.0.0 Mobile Safari/537.36',
            COOKIE_KEY: 'uc_cookie',
            EXT_KEY: 'uccookie',
        });
        this._access = null;
    }

    /** refresh_token 换 access_token，新 refresh_token 写回（同 UCTokenHandler.refreshToken） */
    accessToken() {
        if (this._access === null) {
            this._access = '';
            const refresh = cred(TOKEN_KEY);
            if (refresh) {
                const { req: id } = device();
                const r = http(CODE_API + '/token', { body: { ...deviceParams(), req_id: id, device_id: DEVICE_ID, refresh_token: refresh },
                    headers: { Accept: 'application/json, text/plain, */*', 'User-Agent': TV_UA } });
                const data = (r.code === 200 ? parseJson(r.content) : {}).data || {};
                this._access = data.access_token || '';
                if (data.refresh_token && data.refresh_token !== refresh) setCred(TOKEN_KEY, data.refresh_token);
            }
        }
        return this._access;
    }

    tvDownload(token, saveFid) {
        const { ts, req: id } = device();
        const params = { ...deviceParams(), req_id: id, access_token: token, device_id: DEVICE_ID, method: 'streaming',
            group_by: 'source', fid: saveFid, resolution: 'low,normal,high,super,2k,4k', support: 'dolby_vision' };
        const r = http(OPEN_API + '/file?' + qs(params), { headers: {
            'content-type': 'text/plain;charset=UTF-8', 'User-Agent': TV_UA, 'x-pan-tm': ts,
            'x-pan-token': sha256(`GET&/file&${ts}&${SIGN_KEY}`), 'x-pan-client-id': CLIENT_ID } });
        const j = parseJson(r.content || '{}');
        if (r.code !== 200) throw new PanError('UC TV 接口错误: ' + j.error_info);
        return j.data.video_info[0].url;
    }

    play(playId, flag) {
        this.needCookie();
        const [fid, ftoken, sid, stoken] = (playId + '++++++').split('++');
        const saveFid = this.save(fid, ftoken, sid, stoken);
        if (QuarkLike.qualityOf(flag).includes('原画')) {
            const token = this.accessToken();
            const url = token ? this.tvDownload(token, saveFid) : this.downloadUrl(saveFid);
            return { parse: 0, url, header: { 'User-Agent': this.UA, Referer: this.REFERER, Cookie: this.cookie } };
        }
        return { parse: 0, url: this.transcodingUrl(saveFid, flag), header: { 'User-Agent': this.UA, Referer: this.REFERER } };
    }
}

export const uc = new UC();
