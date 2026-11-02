// 内置瓜子，对应 itv 单线路包 custom_spider_modified.jar 的 csp_Gz360。
// 请求：参数 JSON 用随机 key/iv 做 AES-CBC → 大写 hex，key/iv 用 RSA 公钥加密，再 MD5 签名；响应同理用 RSA 私钥解出 key/iv 再 AES 解密。
// RSA 走 App 原生 rsaX（CryptoJS 没有 RSA）。去掉了原 jar 的 parseJsonAndSave / addDanmaku 上报。
import { Crypto } from 'assets://js/lib/cat.js';

const PUB = '-----BEGIN PUBLIC KEY-----\nMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDUM5+/y8sPsWkd1/RQS64X259E\nUwxFXFE5HlA65MqrxnPs0JqoSRojSDy5QhwvROlaD6TwRQHKMY2OAZ6SnQeUJsCh\nTEFIR9qUkwrs3/MVUMxjsv6JS6Oe/juclyJGTgVmDhB55EafXsD0SQYVj/QXXsxR\n6ewR5E2kL52yAAD4yQIDAQAB\n-----END PUBLIC KEY-----';
const PRI = '-----BEGIN PRIVATE KEY-----\nMIICdgIBADANBgkqhkiG9w0BAQEFAASCAmAwggJcAgEAAoGAe6hKrWLi1zQmjTT1ozbE4QdFeJGNxubxld6GrFGximxfMsMB6BpJhpcTouAqywAFppiKetUBBbXwYsYU1wNr648XVmPmCMCy4rY8vdliFnbMUj086DU6Z+/oXBdWU3/b1G0DN3E9wULRSwcKZT3wj/cCI1vsCm3gj2R5SqkA9Y0CAwEAAQKBgAJH+4CxV0/zBVcLiBCHvSANm0l7HetybTh/j2p0Y1sTXro4ALwAaCTUeqdBjWiLSo9lNwDHFyq8zX90+gNxa7c5EqcWV9FmlVXr8VhfBzcZo1nXeNdXFT7tQ2yah/odtdcx+vRMSGJd1t/5k5bDd9wAvYdIDblMAg+wiKKZ5KcdAkEA1cCakEN4NexkF5tHPRrR6XOY/XHfkqXxEhMqmNbB9U34saTJnLWIHC8IXys6Qmzz30TtzCjuOqKRRy+FMM4TdwJBAJQZFPjsGC+RqcG5UvVMiMPhnwe/bXEehShK86yJK/g/UiKrO87h3aEu5gcJqBygTq3BBBoH2md3pr/W+hUMWBsCQQChfhTIrdDinKi6lRxrdBnn0Ohjg2cwuqK5zzU9p/N+S9x7Ck8wUI53DKm8jUJE8WAG7WLj/oCOWEh+ic6NIwTdAkEAj0X8nhx6AXsgCYRql1klbqtVmL8+95KZK7PnLWG/IfjQUy3pPGoSaZ7fdquG8bq8oyf5+dzjE/oTXcByS+6XRQJAP/5ciy1bL3NhUhsaOVy55MHXnPjdcTX0FaLi+ybXZIfIQ2P4rb19mVq1feMbCXhz+L1rG8oat5lYKfpe8k83ZA==\n-----END PRIVATE KEY-----';
const SALT = '*&zvdvdvddbfikkkumtmdwqppp?|4Y!s!2br';
let host = 'https://api.h27sq4f.com';
let token = '', userId = '', playRef = 'http://WJiZxLXA2.com/';

const C = Crypto.enc;
const rand16 = () => Array.from({ length: 16 }, () => 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'[Math.random() * 62 | 0]).join('');
const aesOpt = iv => ({ iv: C.Utf8.parse(iv), mode: Crypto.mode.CBC, padding: Crypto.pad.Pkcs7 });

// 原始请求，返回 {code, data:{response_key, keys}}
function raw(path, param = {}) {
    const k = rand16(), iv = rand16();
    const requestKey = Crypto.AES.encrypt(JSON.stringify(param), C.Utf8.parse(k), aesOpt(iv)).ciphertext.toString().toUpperCase();
    const p = {
        token_id: '', token, phone_type: '1', request_key: requestKey, app_id: '1',
        time: String(Math.floor(Date.now() / 1000)), keys: rsaX('RSA/PKCS1', true, true, JSON.stringify({ key: k, iv }), false, PUB, true),
    };
    p.signature = Crypto.MD5(Object.entries(p).map(([a, b]) => a + '=' + b).join(',') + SALT).toString().toUpperCase();
    p.phone_model = 'xiaomi-22021211rc';
    p.ad_version = '1';
    const r = req(host + path, {
        method: 'post', timeout: 15000, data: Object.entries(p).map(([a, b]) => a + '=' + encodeURIComponent(b)).join('&'),
        headers: {
            lang: 'zh_cn', 'User-Agent': 'okhttp/3.12.0', 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            code: 'GZ0313', version: '2606029', packagename: 'com.v54f07a912.t4ee50f184.dbb1e7669f20260721',
            ver: '3.0.4.8', 'api-ver': '3.0.4.8', referer: host,
        },
    });
    return JSON.parse(r.content || '{}');
}

function decrypt(res) {
    const d = res.data || {};
    if (!d.keys) return {};
    const kv = JSON.parse(rsaX('RSA/PKCS1', false, false, d.keys, true, PRI, false) || '{}');
    const out = Crypto.AES.decrypt({ ciphertext: C.Hex.parse(d.response_key) }, C.Utf8.parse(kv.key), aesOpt(kv.iv));
    return JSON.parse(out.toString(C.Utf8) || '{}');
}

const api = (path, param) => decrypt(raw(path, param));

// 设备 key：time(4) + rand(4) + 3,0 + hash(android_id)(4) + hash(base64(HmacSHA1))(4)，均大端
function jhash(s) { let h = 0; for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0; return h; }
function oldKey() {
    const be = n => [(n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255];
    const bytes = [...be(Math.floor(Date.now() / 1000)), ...be(Math.random() * 2 ** 32 | 0), 3, 0, ...be(jhash('1a2b3c4d5e6f7g8h'))];
    const wa = b => C.Hex.parse(b.map(x => x.toString(16).padStart(2, '0')).join(''));
    const mac = Crypto.HmacSHA1(wa(bytes), 'd6fc3a4a06adbde89223bvefedc24fecde188aaa9161').toString(C.Base64);
    return wa([...bytes, ...be(jhash(mac))]).toString(C.Base64);
}

function login() {
    const p = { new_key: Crypto.SHA1(Math.random().toString(36) + Date.now()).toString().toUpperCase(), old_key: oldKey() };
    let r = raw('/App/Authentication/Device/signIn', p);
    if (r.code === 403) r = raw('/App/Authentication/Device/signUp', { ...p, recommend_id: '' });
    if (r.code !== 200) return;
    const d = decrypt(r);
    if (d.token) { token = d.token; userId = d.app_user_id; }
}

const ADULT = /伦理|成人|三级/;
const vods = (list, name = 'vod_name', pic = 'vod_pic', score = 'vod_scroe') => (list || [])
    .filter(i => !ADULT.test(i.tags || ''))
    // ponytail: 原 jar 封面追加 @User-Agent=Dalvik/...，App 不解析该后缀，省略
    .map(i => ({ vod_id: String(i.vod_id), vod_name: i[name], vod_pic: i[pic], vod_remarks: i.new_continue || '评分:' + (i[score] ?? '') }));

const years = n => [{ n: '全部', v: '0' }, ...Array.from({ length: n }, (_, i) => ({ n: String(2026 - i), v: String(2026 - i) }))];
const kv = (...a) => [{ n: '全部', v: '0' }, ...a.map(x => typeof x === 'string' ? { n: x, v: x } : x)];
const SORT = { key: 'sort', name: '排序', value: [{ n: '最新', v: 'd_id' }, { n: '最热', v: 'hits' }, { n: '评分', v: 'score' }] };
const FILTERS = {
    1: [
        { key: 'sub', name: '类型', value: kv(...['动作', '喜剧', '爱情', '科幻', '恐怖', '剧情', '战争', '纪录'].map(v => ({ n: v + '片', v }))) },
        { key: 'area', name: '地区', value: kv('大陆', '香港', '台湾', '美国', '日本', '韩国', '欧洲') },
        { key: 'year', name: '年份', value: years(9) }, SORT,
    ],
    2: [
        { key: 'sub', name: '类型', value: kv('国产剧', '港台剧', '日韩剧', '欧美剧', '海外剧') },
        { key: 'area', name: '地区', value: kv('内地', '韩国', '香港', '台湾', '日本', '美国', '泰国', '英国') },
        { key: 'year', name: '年份', value: years(9) }, SORT,
    ],
    3: [{ key: 'area', name: '地区', value: kv('内地', '港台', '日韩', '欧美') }, { key: 'year', name: '年份', value: years(9) }, SORT],
    4: [{ key: 'area', name: '地区', value: kv('国产', '日本', '欧美') }, { key: 'year', name: '年份', value: years(11) }, SORT],
    64: [SORT],
};

export default {
    init(ext) {
        let cfg = {};
        try { cfg = typeof ext === 'string' ? JSON.parse(ext || '{}') : (ext || {}); } catch (e) {}
        if (cfg.sites) host = String(cfg.sites).split(',')[0].trim().replace(/\/$/, '');
        // ponytail: 原 jar 用静态 token 跨实例复用并先试 refresh；这里每次 init 直接 signIn/signUp
        login();
        const u = api('/App/UserInfo/getUserInfo', {});
        if (u.playRef) playRef = u.playRef;
    },

    home(filter) {
        const classes = [['1', '电影'], ['2', '剧集'], ['3', '综艺'], ['4', '动漫'], ['64', '短剧']].map(([type_id, type_name]) => ({ type_id, type_name }));
        return JSON.stringify(filter ? { class: classes, filters: FILTERS } : { class: classes });
    },

    homeVod() {
        return JSON.stringify({ list: vods(api('/App/IndexList/choiceList', { pid: '1' }).list, 'c_name', 'c_pic', 'vod_douban_score') });
    },

    category(tid, pg, filter, extend) {
        const e = extend || {};
        const list = vods(api('/App/IndexList/indexList', {
            area: e.area || '0', year: e.year || '0', pageSize: '30', sort: e.sort || 'd_id', sub: e.sub || '0', page: String(pg), tid,
        }).list);
        return JSON.stringify({ list, page: parseInt(pg), pagecount: list.length ? parseInt(pg) + 1 : parseInt(pg), limit: 30 });
    },

    detail(id) {
        const info = api('/App/IndexPlay/playInfo', { token_id: userId, vod_id: id, mobile_time: String(Math.floor(Date.now() / 1000)), token }).vodInfo || {};
        const urls = (api('/App/Resource/Vurl/show', { vurl_cloud_id: '2', vod_d_id: id }).list || []).map((it, i) => {
            const play = it.play || {};
            const q = ['3840', '2160', '1080', '720', '480', '360', '240'].find(r => play[r] && play[r].param) || '';
            const title = (it.title || String(i + 1)) + (q ? ' [' + q + 'P]' : '');
            return title + '$' + C.Base64.stringify(C.Utf8.parse(q ? play[q].param : ''));
        });
        return JSON.stringify({ list: [{
            vod_id: id, vod_name: info.vod_name, vod_pic: info.vod_pic, vod_remarks: info.new_continue, vod_year: info.vod_addtime,
            vod_area: info.vod_area, vod_actor: info.vod_actor, vod_director: info.vod_director, vod_content: info.vod_use_content,
            vod_play_from: '瓜子视频', vod_play_url: urls.join('#'),
        }] });
    },

    search(key, quick, pg) {
        return JSON.stringify({ list: vods(api('/App/Index/findMoreVod', { keywords: key, order_val: '1' }).list) });
    },

    play(flag, id, flags) {
        const p = {};
        for (const s of C.Base64.parse(id).toString(C.Utf8).split('&')) {
            const a = s.split('=');
            if (a.length === 2) p[a[0] === 'vod_d_id' ? 'vod_id' : a[0]] = a[1];
        }
        const url = api('/App/Resource/VurlDetail/showOne', p).url || '';
        return JSON.stringify({ parse: 0, url, header: { 'User-Agent': 'Lavf/57.83.100', Referer: playRef } });
    },
};
