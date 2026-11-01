// 内置 Emby 站点，对应 spider1202.jar 的 csp_Emby（itv 更新包 local_java.json 里的 52 个 Emby 站）。
// ext：{name, hosts:{线路名:地址}, username, password, client, client_version, device_name, device_id, online?, playBack?, player_ua?}
// 行为对齐 jar：多线路认证、在线数限制（101.43.28.189:3000/api/online|devices）、播放回传（EmbyMonitor）。

const MONITOR = 'http://101.43.28.189:3000';
const PLAYER_UA = 'Hills Windows/0.4.0 (windows; 26100.ge_release.240331-1435)';
// PlaybackInfo 的 DeviceProfile，原样取自 jar
const PROFILE = '{"DeviceProfile":{"SubtitleProfiles":[{"Method":"Embed","Format":"ass"},{"Format":"ssa","Method":"Embed"},{"Format":"subrip","Method":"Embed"},{"Format":"sub","Method":"Embed"},{"Method":"Embed","Format":"pgssub"},{"Format":"subrip","Method":"External"},{"Method":"External","Format":"sub"},{"Method":"External","Format":"ass"},{"Format":"ssa","Method":"External"},{"Method":"External","Format":"vtt"},{"Method":"External","Format":"ass"},{"Format":"ssa","Method":"External"}],"CodecProfiles":[{"Codec":"h264","Type":"Video","ApplyConditions":[{"Property":"IsAnamorphic","Value":"true","Condition":"NotEquals","IsRequired":false},{"IsRequired":false,"Value":"high|main|baseline|constrained baseline","Condition":"EqualsAny","Property":"VideoProfile"},{"IsRequired":false,"Value":"80","Condition":"LessThanEqual","Property":"VideoLevel"},{"IsRequired":false,"Value":"true","Condition":"NotEquals","Property":"IsInterlaced"}]},{"Codec":"hevc","ApplyConditions":[{"Property":"IsAnamorphic","Value":"true","Condition":"NotEquals","IsRequired":false},{"IsRequired":false,"Value":"high|main|main 10","Condition":"EqualsAny","Property":"VideoProfile"},{"Property":"VideoLevel","Value":"175","Condition":"LessThanEqual","IsRequired":false},{"IsRequired":false,"Value":"true","Condition":"NotEquals","Property":"IsInterlaced"}],"Type":"Video"}],"MaxStreamingBitrate":40000000,"TranscodingProfiles":[{"Container":"ts","AudioCodec":"aac,mp3,wav,ac3,eac3,flac,opus","VideoCodec":"hevc,h264,mpeg4","BreakOnNonKeyFrames":true,"Type":"Video","MaxAudioChannels":"6","Protocol":"hls","Context":"Streaming","MinSegments":2}],"DirectPlayProfiles":[{"Container":"mov,mp4,mkv,hls,webm","Type":"Video","VideoCodec":"h264,hevc,dvhe,dvh1,h264,hevc,hev1,mpeg4,vp9","AudioCodec":"aac,mp3,wav,ac3,eac3,flac,truehd,dts,dca,opus,pcm,pcm_s24le"}],"ResponseProfiles":[{"MimeType":"video/mp4","Type":"Video","Container":"m4v"}],"ContainerProfiles":[],"MusicStreamingTranscodingBitrate":40000000,"MaxStaticBitrate":40000000}}';
const LIST_FIELDS = 'BasicSyncInfo,CanDelete,Container,PrimaryImageAspectRatio,ProductionYear,CommunityRating,CriticRating';

let cfg = {};
let hosts = [];      // [{name, url}]
let auth = null;     // {base, token, userId, session:{DeviceId, DeviceName, Client, ApplicationVersion}}
let deviceId = '';   // ext.device_id，用于 X-Emby-Authorization（伪装的客户端设备）
let playing = null;  // 当前播放：{base, itemId, mediaSourceId, session, last}

function strip(u) { return String(u || '').replace(/\/+$/, ''); }

// 对应 Emby.b：# 和 $ 是播放串分隔符，替换掉
function clean(s) { return String(s || '').replace(/#/g, '-').replace(/\$/g, '|').trim(); }

// 本机设备 id/名（Swift 启动时写入 cache_device_id / cache_device_name，对应 jar 的 DeviceInfoHelper）
function localDevice() { return { id: local.get('', 'device_id'), name: local.get('', 'device_name') }; }

// 请求头（对应 Emby.u + Emby.e）
function headers(token) {
    const client = cfg.client || 'AfuseKt/(Linux;Android Release)Player';
    const version = cfg.client_version || '2.9.7.5';
    const h = {
        'User-Agent': client + '/' + version,
        'X-Emby-Authorization': 'MediaBrowser Client="' + client + '", Device="' + (cfg.device_name || 'Xiaomi-23127PN0CC')
            + '", DeviceId="' + deviceId + '", Version="' + version + '"',
        'Content-Type': 'application/json; charset=UTF-8',
        'Accept': '*/*',
    };
    if (token) { h['X-Emby-Token'] = token; h['X-MediaBrowser-Token'] = token; }
    return h;
}

// 拼查询参数（对应 Emby.n）
function withQuery(url, params) {
    const q = Object.entries(params || {}).map(([k, v]) => encodeURIComponent(k) + '=' + encodeURIComponent(v == null ? '' : v));
    return q.length ? url + (url.includes('?') ? '&' : '?') + q.join('&') : url;
}

// 认证结果附带的查询参数（对应 Emby.m）
function sessionQuery(a, extra) {
    const s = a.session || {};
    return Object.assign({ 'X-Emby-Client': s.Client || '', 'X-Emby-Device-Name': s.DeviceName || '',
        'X-Emby-Device-Id': s.DeviceId || '', 'X-Emby-Client-Version': s.ApplicationVersion || '', 'X-Emby-Token': a.token }, extra || {});
}
// 认证（对应 getAccessToken）：缓存 30 天，键同 jar（站名 + 用户名）；按线路顺序尝试，全部失败才报错。
// ponytail: jar 按运营商（ipinfo.io/myip.ipip.net/ip-api.com）过滤线路并 6 秒测速排序；这里按 ext.hosts 顺序依次回退，线路多且慢时再加测速
function login(force) {
    const key = 'new_emby_' + (cfg.name || '') + '_' + (cfg.username || '');
    if (!force && !auth) {
        try { auth = JSON.parse(local.get('emby', key) || 'null'); } catch (e) { auth = null; }
        if (auth && Date.now() - (auth.time || 0) > 30 * 86400000) auth = null;
    }
    if (!force && auth && auth.token) return auth;
    const body = JSON.stringify({ Username: cfg.username || '', Pw: cfg.password || '' });
    let last = '所有线路认证均失败';
    // 已认证过的线路优先
    const order = auth ? hosts.slice().sort((x, y) => (y.url === auth.base) - (x.url === auth.base)) : hosts;
    for (const h of order) {
        const r = req(h.url + '/emby/Users/AuthenticateByName', { method: 'post', body, headers: headers(), timeout: 15000 });
        if (r.code !== 200) { last = '认证失败,状态码: ' + r.code; continue; }
        let j = null;
        try { j = JSON.parse(r.content || ''); } catch (e) { j = null; }
        if (!j || !j.AccessToken) { last = 'invalid auth response'; continue; }
        const s = j.SessionInfo || {};
        auth = { base: h.url, token: j.AccessToken, userId: (j.User || {}).Id || '', time: Date.now(),
            session: { DeviceId: s.DeviceId || deviceId, DeviceName: s.DeviceName || '', Client: s.Client || '', ApplicationVersion: s.ApplicationVersion || '' } };
        local.set('emby', key, JSON.stringify(auth));
        return auth;
    }
    throw new Error(last);
}

// GET 接口：401/403 时重新认证一次（对应 jar 的 c() + getAccessToken(force)）
function api(path, params) {
    for (let i = 0; i < 2; i++) {
        const a = login(i > 0);
        const r = req(withQuery(a.base + path.replace('{uid}', a.userId), sessionQuery(a, params)), { headers: headers(a.token), timeout: 15000 });
        if (r.code === 401 || r.code === 403) continue;
        if (r.code !== 200) return null;
        try { return JSON.parse(r.content || '{}'); } catch (e) { return null; }
    }
    return null;
}

// 封面图（对应 Emby.i）
function pic(it) {
    const tag = (it.ImageTags || {}).Primary;
    return tag ? auth.base + '/emby/Items/' + it.Id + '/Images/Primary?maxWidth=400&tag=' + tag + '&quality=90' : '';
}

function toVod(it) {
    return { vod_id: it.Id, vod_name: String(it.Name || '').replace(/\n/g, ' ').trim(), vod_pic: pic(it),
        vod_remarks: it.ProductionYear == null ? '' : String(it.ProductionYear) };
}

// 在线数限制（对应 playerContent 开头）：在线数 >= online 且本机不在设备列表里则拒绝；接口异常时放行
function onlineBlocked() {
    const limit = cfg.online == null ? 2 : Number(cfg.online);
    if (!(limit > 0)) return '';
    try {
        const o = req(MONITOR + '/api/online/' + (cfg.name || ''), { timeout: 8000 });
        const n = parseInt(String(o.content || '').trim(), 10);
        if (o.code !== 200 || !(n >= limit)) return '';
        const d = req(MONITOR + '/api/devices/' + (cfg.name || ''), { timeout: 8000 });
        const me = localDevice().id;
        if (me && d.code === 200 && String(d.content || '').trim().includes(me)) return '';
        return '当前在线设备数(' + n + ')已达上限(' + limit + ')';
    } catch (e) { return ''; }
}

// 线路列表：ext.hosts 对象（线路名→地址），没有时退回 ext.url/server
function parseHosts() {
    const out = [];
    for (const [name, url] of Object.entries(cfg.hosts || {})) if (url) out.push({ name, url: strip(url) });
    if (!out.length && (cfg.url || cfg.server)) out.push({ name: 'EMBY', url: strip(cfg.url || cfg.server) });
    return out;
}

// 播放器请求头（对应 Emby.j）
function playerHeaders() {
    return { 'User-Agent': cfg.player_ua || cfg.mzxx_player_ua || PLAYER_UA, 'Accept': '*/*', 'Icy-MetaData': '1', 'Connection': 'close' };
}

function fail(msg) { return JSON.stringify({ parse: 0, url: '', header: playerHeaders(), msg }); }

// 集列表（对应 Emby.f）：非文件夹直接一集；剧集先按 Episode 递归拉，没有再走 Seasons → Episodes，最后退回子项
function episodes(id) {
    const it = api('/emby/Users/{uid}/Items/' + id);
    if (!it) return [];
    if (!it.IsFolder) return [String(it.Name || '').trim() + '$' + it.Id];
    const items = (j) => (j && j.Items) || [];
    const eps = items(api('/emby/Users/{uid}/Items', { ParentId: id, Recursive: 'true', IncludeItemTypes: 'Episode',
        Fields: 'SeasonName,ParentIndexNumber,IndexNumber,SortName,' + LIST_FIELDS, ImageTypeLimit: '1', StartIndex: '0', EnableUserData: 'true' }));
    if (eps.length) return eps.map(e => (e.SeasonName ? clean(e.SeasonName) + '|' : '') + clean(e.Name) + '$' + e.Id);
    const out = [];
    for (const s of items(api('/emby/Shows/' + id + '/Seasons', { UserId: auth.userId, EnableImages: 'true',
        Fields: 'BasicSyncInfo,CanDelete,Container,PrimaryImageAspectRatio,ProductionYear,CommunityRating', EnableUserData: 'true', EnableTotalRecordCount: 'false' }))) {
        for (const e of items(api('/emby/Shows/' + s.Id + '/Episodes', { SeasonId: s.Id, Fields: 'BasicSyncInfo,CanDelete,CommunityRating,PrimaryImageAspectRatio,ProductionYear,Overview' })))
            out.push(clean(s.Name) + '|' + clean(e.Name) + '$' + e.Id);
    }
    if (out.length) return out;
    return items(api('/emby/Users/{uid}/Items', { ParentId: id, Fields: LIST_FIELDS, ImageTypeLimit: '1', StartIndex: '0', EnableUserData: 'true' }))
        .map(e => clean(e.Name) + '$' + e.Id);
}
// Emby 回传（对应 EmbyMonitor.j / l）：POST {base}/emby/Sessions/Playing[/Progress|/Stopped]
function embyReport(p, path, body) {
    const s = p.session || {};
    const url = withQuery(p.base + '/emby/Sessions/Playing' + path, { 'X-Emby-Token': p.token, 'X-Emby-Device-Id': s.DeviceId || '',
        'X-Emby-Client': s.Client || '', 'X-Emby-Device-Name': s.DeviceName || '' });
    const b = Object.assign({ ItemId: p.itemId, PlaySessionId: p.sessionId }, p.mediaSourceId ? { MediaSourceId: p.mediaSourceId } : {}, body || {});
    try { req(url, { method: 'post', body: JSON.stringify(b), headers: { 'Content-Type': 'application/json', 'User-Agent': cfg.client || 'AfuseKt/(Linux;Android Release)Player' }, timeout: 8000 }); } catch (e) { }
}

// 在线设备登记（对应 EmbyMonitor.j 里的 /api/playback）
function onlineReport() {
    if (!((cfg.online == null ? 2 : Number(cfg.online)) > 0)) return;
    const d = localDevice();
    try { req(MONITOR + '/api/playback', { method: 'post', body: JSON.stringify({ emby_id: cfg.name || '', device_id: d.id, device_name: d.name }), headers: { 'Content-Type': 'application/json' }, timeout: 8000 }); } catch (e) { }
}

export default {
    init(ext) {
        cfg = typeof ext === 'string' ? (ext.trim().startsWith('{') ? JSON.parse(ext) : {}) : (ext || {});
        hosts = parseHosts();
        deviceId = cfg.device_id || '324d11a2745e28a7';
        auth = null;
        playing = null;
    },

    home() {
        const j = api('/emby/Users/{uid}/Views');
        if (!j) return JSON.stringify({ class: [], list: [], msg: '获取首页失败' });
        const cls = (j.Items || []).filter(it => it.Name && !it.Name.includes('播放列表') && !it.Name.includes('相机'))
            .map(it => ({ type_id: it.Id, type_name: it.Name }));
        return JSON.stringify({ class: cls, list: [] });
    },

    homeVod() { return JSON.stringify({ list: [] }); },

    category(tid, pg) {
        const page = parseInt(pg || '1', 10) || 1;
        const j = api('/emby/Users/{uid}/Items', { SortBy: 'DateLastContentAdded,SortName', IncludeItemTypes: 'Movie,Series', SortOrder: 'Descending',
            ParentId: tid, Recursive: 'true', Limit: '10', ImageTypeLimit: '1', StartIndex: String((page - 1) * 10),
            EnableImageTypes: 'Primary,Backdrop,Thumb,Banner', Fields: LIST_FIELDS + ',Status,EndDate,Path', EnableUserData: 'true' }) || {};
        const total = j.TotalRecordCount || 0;
        const list = (j.Items || []).map(toVod);
        return JSON.stringify({ page, pagecount: page * 10 < total ? page + 1 : page, limit: list.length, total, list });
    },

    detail(id) {
        const it = api('/emby/Users/{uid}/Items/' + id);
        if (!it) return JSON.stringify({ list: [], msg: '获取详情超时,请稍后重试' });
        const vod = { vod_id: id, vod_name: it.Name || '', vod_pic: pic(it), type_name: (it.Genres || [])[0] || '',
            vod_year: it.ProductionYear == null ? '' : String(it.ProductionYear),
            vod_content: String(it.Overview || '').replace(/ /g, ' ').replace(/\n\n/g, '\n').trim() };
        const eps = episodes(id).join('#');
        // jar：每条线路一组，集列表相同；选线路 = 播放时用对应地址
        if (eps) {
            const lines = hosts.length ? hosts : [{ name: 'EMBY' }];
            vod.vod_play_from = lines.map(h => h.name).join('$$$');
            vod.vod_play_url = lines.map(() => eps).join('$$$');
        }
        return JSON.stringify({ list: [vod] });
    },

    search(key, quick, pg) {
        const page = parseInt(pg || '1', 10) || 1;
        const j = api('/emby/Users/{uid}/Items', { SortBy: 'SortName', SortOrder: 'Ascending', Fields: 'ProductionYear', StartIndex: String((page - 1) * 15),
            EnableImageTypes: 'Primary,Backdrop,Thumb', ImageTypeLimit: '1', Recursive: 'true', SearchTerm: key,
            IncludeItemTypes: 'Movie,Series,BoxSet', GroupProgramsBySeries: 'true', Limit: '15', EnableTotalRecordCount: 'true' }) || {};
        return JSON.stringify({ list: (j.Items || []).map(toVod) });
    },

    play(flag, id) {
        const blocked = onlineBlocked();
        if (blocked) return fail(blocked);
        id = String(id || '').split(',')[0];
        const m = id.startsWith('http') && id.match(/\/(?:videos|items)\/([a-zA-Z0-9]+)/i);
        if (m) id = m[1];
        let a;
        try { a = login(false); } catch (e) { return fail('获取Emby服务器信息出错'); }
        const base = (hosts.find(h => h.name === flag) || {}).url || a.base;
        const r = req(withQuery(base + '/emby/Items/' + id + '/PlaybackInfo', sessionQuery(a, { UserId: a.userId, IsPlayback: 'false',
            AutoOpenLiveStream: 'false', StartTimeTicks: '0', MaxStreamingBitrate: '2147483647' })), { method: 'post', body: PROFILE, headers: headers(a.token), timeout: 15000 });
        if (r.code !== 200 || !String(r.content || '').trim()) return fail('获取播放地址失败,状态码: ' + r.code);
        let sources = [];
        try { sources = JSON.parse(r.content).MediaSources || []; } catch (e) { sources = []; }
        if (!sources.length) return fail('获取Emby服务器信息出错');
        // ponytail: jar 在地址后拼 #media_source_id=…&DeviceId=… 供 EmbyMonitor 识别，iOS 播放器直接回调 report()，不需要；也不走 jar 的多线程代理
        const urls = [];
        for (const s of sources) {
            let p = String(s.DirectStreamUrl || '');
            if (p && !p.startsWith('/emby')) p = '/emby' + (p.startsWith('/') ? p : '/' + p);
            if (!p) p = '/emby/videos/' + id + '/stream?static=true&MediaSourceId=' + (s.Id || '') + '&api_key=' + a.token;
            urls.push(s.Name || s.DisplayTitle || s.Container || s.Id || 'default', base + p);
        }
        playing = { base, token: a.token, session: a.session, itemId: id, mediaSourceId: sources[0].Id || '', sessionId: '', last: 0 };
        return JSON.stringify({ parse: 0, url: urls, header: playerHeaders() });
    },

    // 播放器回调（Seesee 扩展，对应 EmbyMonitor 轮询 /media）：state = start | progress | pause | stop，pos 为毫秒
    report(state, pos) {
        const p = playing;
        if (!p || cfg.playBack === false) return;
        const ticks = Math.max(0, Math.round(Number(pos) || 0)) * 10000;
        const now = Date.now();
        if (state === 'start') {
            p.sessionId = (p.session.DeviceId || '') + '_' + p.itemId + '_' + Math.floor(now / 1000);
            p.last = now;
            onlineReport();
            embyReport(p, '', {});
        } else if (state === 'stop') {
            embyReport(p, '/Stopped', { PositionTicks: ticks });
            playing = null;
        } else if (now - p.last >= 10000) {
            // 最多每 10 秒一次
            p.last = now;
            onlineReport();
            embyReport(p, '/Progress', { PositionTicks: ticks, IsPaused: state === 'pause', PlayMethod: 'DirectStream' });
        }
    },
};
