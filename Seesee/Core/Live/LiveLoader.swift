import Foundation

/// 拉取直播源与 EPG（对应 LiveViewModel）
enum LiveLoader {
    /// 直播源文本：url 支持 http(s)，api 为 JS 爬虫时调用其 live(url)
    static func groups(_ live: Live, fetch: HTTP.Fetch) async throws -> (groups: [LiveGroup], live: Live) {
        guard live.groups.isEmpty else { return (live.groups, live) }
        let req = try HTTP.get(live.url, headers: live.header, timeout: TimeInterval(live.timeout))
        let text = HTTP.string(try await fetch(req))
        var l = live
        if l.epg.isEmpty, LiveParser.isM3U(text) { l.epg = LiveParser.m3uEPG(text) }
        return (LiveParser.parse(text, live: l), l)
    }

    /// xmltv 节目单（所有频道），失败返回空
    static func xmltv(_ urls: [String], timeZone: TimeZone, fetch: HTTP.Fetch) async -> [String: [Programme]] {
        var out: [String: [Programme]] = [:]
        for u in urls {
            guard let req = try? HTTP.get(u, timeout: 30), let data = try? await fetch(req) else { continue }
            out.merge(XMLTV.parse(data.gunzipped ?? data, timeZone: timeZone)) { a, _ in a }
        }
        return out
    }

    /// 按频道查询的 EPG 接口
    static func programmes(_ channel: Channel, timeZone: TimeZone, fetch: HTTP.Fetch) async -> [Programme] {
        guard channel.epg.hasPrefix("http"), let req = try? HTTP.get(EPG.url(channel.epg, timeZone: timeZone), timeout: 10),
              let data = try? await fetch(req) else { return [] }
        return EPG.parse(HTTP.string(data), timeZone: timeZone)
    }
}

extension Live {
    var zone: TimeZone { TimeZone(identifier: timeZone) ?? .current }
}
