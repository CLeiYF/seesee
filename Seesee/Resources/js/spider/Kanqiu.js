// 内置 88看球，对应 jar 的 csp_Kanqiu（AndroidCatVodSpider/spider/Kanqiu.java）。
// ext 可选：以 http 开头时作为站点域名。线路是第三方网页播放器，交给 App 嗅探（parse:1）。
import { load, Crypto } from 'assets://js/lib/cat.js';

const HEADERS = { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36' };
const DEFAULT_PIC = 'https://pic.imgdb.cn/item/657673d6c458853aeff94ab9.jpg';
const CLASSES = [['', '全部直播'], ['1', '篮球直播'], ['8', '足球直播'], ['21', '其他直播']];
const f = pairs => [{ key: 'cateId', name: '类型', value: pairs.map(([n, v]) => ({ n, v })) }];
const FILTERS = {
    1: f([['NBA', '1'], ['CBA', '2'], ['篮球综合', '4'], ['纬来体育', '21']]),
    8: f([['英超', '8'], ['西甲', '9'], ['意甲', '10'], ['欧冠', '12'], ['欧联', '13'], ['德甲', '14'], ['法甲', '15'], ['欧国联', '16'],
        ['足总杯', '27'], ['国王杯', '33'], ['中超', '7'], ['亚冠', '11'], ['足球综合', '23'], ['欧协联', '28'], ['美职联', '26']]),
    // 原 Java 把这组挂在 "29" 下，但分类 id 是 "21"，这里挂到实际分类上
    21: f([['网球', '29'], ['斯洛克', '30'], ['MLB', '38'], ['UFC', '32'], ['NFL', '25'], ['CCTV5', '18']]),
};

let host = 'https://www.88kanqiu.tw';

function get(url) { return req(url, { headers: HEADERS, timeout: 15000 }).content || ''; }

function txt(el) { return el.text().replace(/\s+/g, ' ').trim(); }

export default {
    init(ext) { if (typeof ext === 'string' && ext.startsWith('http')) host = ext.replace(/\/+$/, ''); },

    home(filter) {
        return JSON.stringify({ class: CLASSES.map(([type_id, type_name]) => ({ type_id, type_name })), filters: FILTERS });
    },

    homeVod() { return JSON.stringify({ list: [] }); },

    category(tid, pg, filter, extend) {
        const cate = (extend || {}).cateId || tid;
        const $ = load(get(host + (cate ? '/match/' + cate + '/live' : '')));
        const list = $('.list-group-item').toArray().map(e => {
            const li = $(e), btn = li.find('.btn.btn-primary').first();
            const pic = li.find('.col-xs-1').eq(0).find('img').attr('src') || DEFAULT_PIC;
            return {
                vod_id: host + (btn.attr('href') || ''), // 未开赛时没有按钮链接，id 就等于 host
                vod_name: txt(li.find('.row.d-none')) || txt(li),
                vod_pic: pic.startsWith('http') ? pic : host + pic, vod_remarks: txt(btn),
            };
        });
        return JSON.stringify({ list, page: 1, pagecount: 1, limit: list.length, total: list.length });
    },

    detail(id) {
        if (id.replace(/\/+$/, '') === host) return JSON.stringify({ list: [], msg: '比赛尚未开始' });
        // 原 Java 请求 {id}-url，站点已改为 /live/{gid}/source，返回结构不变
        const src = id.endsWith('/play') ? id.slice(0, -5) + '/source' : id + '-url';
        // 源接口偶尔返回空或非 JSON（比赛未开放信号时），按无线路处理
        let links = [];
        try {
            const data = JSON.parse(get(src)).data.slice(6, -2);
            links = JSON.parse(Crypto.enc.Base64.parse(data).toString(Crypto.enc.Utf8)).links || [];
        } catch (e) {
            return JSON.stringify({ list: [], msg: '暂无直播信号' });
        }
        const eps = links.map(l => (l.name || '') + '$' + (l.url || '').replace(/#/g, '***'));
        return JSON.stringify({ list: [{ vod_id: id, vod_play_from: 'Qile', vod_play_url: eps.join('#') }] });
    },

    search(key, quick, pg) { return JSON.stringify({ list: [] }); },

    play(flag, id, flags) {
        return JSON.stringify({ parse: 1, url: id.replace(/\*\*\*/g, '#'), header: HEADERS });
    },
};
