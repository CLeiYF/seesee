import Foundation

/// 直播配置（对应 bean/Live）
struct Live: Decodable, Hashable, Identifiable {
    var name = ""
    var url = ""
    var api = ""
    var ext = ""
    var logo = ""
    var epg = ""
    var ua = ""
    var origin = ""
    var referer = ""
    var timeZone = ""
    var timeout = 15
    var header: [String: String] = [:]
    var catchup: Catchup?
    var boot = false
    var pass = false
    var groups: [LiveGroup] = []

    var id: String { name }

    init(name: String = "", url: String = "") { (self.name, self.url) = (name, url) }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        name = c.str(AnyKey("name"))
        url = c.str(AnyKey("url"))
        api = c.str(AnyKey("api"))
        ext = c.str(AnyKey("ext"))
        logo = c.str(AnyKey("logo"))
        epg = c.str(AnyKey("epg"))
        ua = c.str(AnyKey("ua"))
        origin = c.str(AnyKey("origin"))
        referer = c.str(AnyKey("referer"))
        timeZone = c.str(AnyKey("timeZone"))
        timeout = max(c.int(AnyKey("timeout")) ?? 15, 1)
        header = c.dict(AnyKey("header"))
        catchup = try? c.decodeIfPresent(Catchup.self, forKey: AnyKey("catchup"))
        boot = (c.int(AnyKey("boot")) ?? 0) == 1 || c.str(AnyKey("boot")) == "true"
        pass = (c.int(AnyKey("pass")) ?? 0) == 1 || c.str(AnyKey("pass")) == "true"
        groups = c.list(AnyKey("groups"))
    }

    /// epg 可写多个，逗号分隔：带 `{` 的是按频道查询的接口，其余是 xmltv 地址
    var epgApi: String { epg.split(separator: ",").map(String.init).first { $0.contains("{") } ?? epg }
    var epgXml: [String] { epg.split(separator: ",").map(String.init).filter { !$0.contains("{") && $0.hasPrefix("http") } }
}

struct LiveGroup: Decodable, Hashable, Identifiable {
    var name = ""
    var pass = ""
    var channels: [Channel] = []

    var id: String { name }

    /// 名称 `分组_密码` 表示加密分组（live.pass 为 true 时不拆）
    init(name: String, livePass: Bool = false) {
        let parts = name.split(separator: "_", maxSplits: 1).map(String.init)
        self.name = parts.first ?? ""
        if !livePass, parts.count == 2 { pass = parts[1] } else if livePass { self.name = name }
        if self.name.isEmpty { self.name = "直播" }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.init(name: c.str(AnyKey("name")))
        let p = c.str(AnyKey("pass"))
        if !p.isEmpty { pass = p }
        channels = c.list(AnyKey("channel"))
    }
}

struct Channel: Decodable, Hashable, Identifiable {
    var name = ""
    var number = ""
    var logo = ""
    var epg = ""
    var tvgId = ""
    var tvgName = ""
    var ua = ""
    var origin = ""
    var referer = ""
    var format = ""
    var parse: Int?
    var header: [String: String] = [:]
    var catchup: Catchup?
    var urls: [String] = []

    var id: String { name }

    init(name: String) { self.name = name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        name = c.str(AnyKey("name"))
        number = c.str(AnyKey("number"))
        logo = c.str(AnyKey("logo"))
        epg = c.str(AnyKey("epg"))
        tvgId = c.str(AnyKey("tvgId"))
        tvgName = c.str(AnyKey("tvgName"))
        ua = c.str(AnyKey("ua"))
        origin = c.str(AnyKey("origin"))
        referer = c.str(AnyKey("referer"))
        format = c.str(AnyKey("format"))
        parse = c.int(AnyKey("parse"))
        header = c.dict(AnyKey("header"))
        catchup = try? c.decodeIfPresent(Catchup.self, forKey: AnyKey("catchup"))
        urls = c.list(AnyKey("urls"))
    }

    /// 播放请求头：header + ua/origin/referer
    var headers: [String: String] {
        var h = header
        if !ua.isEmpty { h["User-Agent"] = ua }
        if !origin.isEmpty { h["Origin"] = origin }
        if !referer.isEmpty { h["Referer"] = referer }
        return h
    }

    /// 线路地址可带 `$线路名`
    static func line(_ url: String) -> (url: String, name: String) {
        let p = url.split(separator: "$", maxSplits: 1).map(String.init)
        return (p.first ?? url, p.count > 1 ? p[1] : "")
    }

    /// 继承直播配置的默认值（对应 Channel.live）
    mutating func inherit(_ live: Live) {
        if ua.isEmpty { ua = live.ua }
        if header.isEmpty { header = live.header }
        if origin.isEmpty { origin = live.origin }
        if referer.isEmpty { referer = live.referer }
        if catchup == nil { catchup = live.catchup }
        if tvgName.isEmpty { tvgName = name }
        if tvgId.isEmpty { tvgId = name }
        if live.epg.contains("{"), !epg.hasPrefix("http") {
            epg = live.epgApi.replacingOccurrences(of: "{id}", with: tvgId).replacingOccurrences(of: "{name}", with: tvgName)
                .replacingOccurrences(of: "{epg}", with: epg)
        }
        if live.logo.contains("{"), !logo.hasPrefix("http") {
            logo = live.logo.replacingOccurrences(of: "{id}", with: tvgId).replacingOccurrences(of: "{name}", with: tvgName)
                .replacingOccurrences(of: "{logo}", with: logo)
        }
    }
}

/// 直播源文本解析：JSON 分组数组 / m3u / txt（对应 api/LiveParser.java）
enum LiveParser {
    static func parse(_ text: String, live: Live) -> [LiveGroup] {
        var live = live
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var groups: [LiveGroup]
        if t.hasPrefix("["), let d = t.data(using: .utf8), let g = try? JSONDecoder().decode([Lossy<LiveGroup>].self, from: d) {
            groups = g.compactMap(\.value)
        } else if isM3U(t) {
            groups = m3u(t, live: &live)
        } else {
            groups = txt(t, live: live)
        }
        var number = 0
        for g in groups.indices {
            for c in groups[g].channels.indices {
                number += 1
                if groups[g].channels[c].number.isEmpty { groups[g].channels[c].number = String(format: "%03d", number) }
                groups[g].channels[c].inherit(live)
            }
        }
        return groups.filter { !$0.channels.isEmpty }
    }

    /// m3u 文件里出现 #EXTM3U / #EXTINF，且不是带 #genre# 的 txt
    static func isM3U(_ t: String) -> Bool {
        t.split(separator: "\n").contains { !$0.contains("#genre#") && ($0.contains("#EXTM3U") || $0.contains("#EXTINF")) }
    }

    /// 从 m3u 头里读到的 epg 地址（x-tvg-url / url-tvg / tvg-url）
    static func m3uEPG(_ t: String) -> String {
        guard let head = t.split(separator: "\n").first(where: { $0.hasPrefix("#EXTM3U") }) else { return "" }
        let line = String(head)
        return attr(line, "x-tvg-url").nonEmpty ?? attr(line, "url-tvg").nonEmpty ?? attr(line, "tvg-url")
    }

    private static func m3u(_ t: String, live: inout Live) -> [LiveGroup] {
        var groups: [LiveGroup] = []
        var setting = Setting()
        var global: Catchup?
        var current: (group: Int, channel: Int)?
        for raw in t.replacingOccurrences(of: "\r", with: "").split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if setting.find(line) {
                setting.check(line)
            } else if line.hasPrefix("#EXTM3U") {
                global = Catchup.from(attrs: line)
                if live.epg.isEmpty { live.epg = m3uEPG(line) }
            } else if line.hasPrefix("#EXTINF:") {
                let gname = attr(line, "group-title")
                let gi = find(&groups, LiveGroup(name: gname, livePass: live.pass))
                let name = line.range(of: ",", options: .backwards).map { String(line[$0.upperBound...]).trimmingCharacters(in: .whitespaces) } ?? ""
                var ch = Channel(name: name)
                ch.ua = attr(line, "http-user-agent")
                ch.tvgName = attr(line, "tvg-name")
                ch.number = attr(line, "tvg-chno")
                ch.logo = attr(line, "tvg-logo")
                ch.tvgId = attr(line, "tvg-id")
                ch.catchup = Catchup.from(attrs: line) ?? global
                let ci = groups[gi].channels.firstIndex { $0.name == name } ?? {
                    groups[gi].channels.append(ch)
                    return groups[gi].channels.count - 1
                }()
                current = (gi, ci)
            } else if !line.hasPrefix("#"), line.contains("://"), let (g, c) = current {
                let parts = line.split(separator: "|").map(String.init)
                if parts.count > 1 { setting.headers(Array(parts[1...])) }
                groups[g].channels[c].urls.append(parts[0])
                setting.apply(&groups[g].channels[c])
                setting = Setting()
            }
        }
        return groups
    }

    private static func txt(_ t: String, live: Live) -> [LiveGroup] {
        var groups: [LiveGroup] = []
        var setting = Setting()
        for raw in t.replacingOccurrences(of: "\r", with: "").split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let parts = line.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if setting.find(line) { setting.check(line) }
            if line.contains("#genre#") {
                setting = Setting()
                groups.append(LiveGroup(name: parts.first ?? "", livePass: live.pass))
                continue
            }
            guard parts.count > 1, parts[1].contains("://") else { continue }
            if groups.isEmpty { groups.append(LiveGroup(name: "")) }
            let g = groups.count - 1
            let ci = groups[g].channels.firstIndex { $0.name == parts[0] } ?? {
                groups[g].channels.append(Channel(name: parts[0]))
                return groups[g].channels.count - 1
            }()
            groups[g].channels[ci].urls += parts[1].split(separator: "#").map(String.init)
            setting.apply(&groups[g].channels[ci])
        }
        return groups
    }

    private static func find(_ groups: inout [LiveGroup], _ g: LiveGroup) -> Int {
        if let i = groups.firstIndex(where: { $0.name == g.name }) { return i }
        groups.append(g)
        return groups.count - 1
    }

    /// 读取 `key="value"`
    static func attr(_ line: String, _ key: String) -> String {
        guard let r = line.range(of: key + "=\"") else { return "" }
        let rest = line[r.upperBound...]
        return rest.firstIndex(of: "\"").map { String(rest[..<$0]).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    /// 频道前的设置行：ua= / referer= / origin= / header= / #EXTVLCOPT / #EXTHTTP / #KODIPROP
    /// ponytail: DRM(license_key) 不处理，KSPlayer 不支持 ClearKey/Widevine
    struct Setting {
        var ua: String?
        var origin: String?
        var referer: String?
        var format: String?
        var parse: Int?
        var header: [String: String]?

        func find(_ l: String) -> Bool {
            ["ua", "parse", "header", "format", "origin", "referer", "#EXTHTTP:", "#EXTVLCOPT:", "#KODIPROP:"].contains { l.hasPrefix($0) }
        }

        mutating func check(_ l: String) {
            func after(_ k: String) -> String? {
                l.range(of: k, options: .caseInsensitive).map { String(l[$0.upperBound...]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "") }
            }
            if l.hasPrefix("#EXTVLCOPT:http-user-agent") || l.hasPrefix("ua") { ua = after("user-agent=") ?? after("ua=") }
            else if l.hasPrefix("#EXTVLCOPT:http-referrer") { referer = after("referrer=") }
            else if l.hasPrefix("#EXTVLCOPT:http-origin") || l.hasPrefix("origin") { origin = after("origin=") }
            else if l.hasPrefix("referer") { referer = after("referer=") }
            else if l.hasPrefix("parse") { parse = after("parse=").flatMap { Int($0) } }
            else if l.hasPrefix("format") || l.contains("manifest_type=") { format = after("format=") ?? after("manifest_type=") }
            else if l.hasPrefix("#EXTHTTP:") || l.hasPrefix("header") {
                let json = after("#EXTHTTP:") ?? after("header=") ?? ""
                if let d = json.data(using: .utf8), let o = try? JSONDecoder().decode(AnyJSON.self, from: d) { header = o.dict }
            } else if l.contains("stream_headers=") || l.contains("common_headers=") {
                headers((after("headers=") ?? "").split(separator: "&").map(String.init))
            }
        }

        mutating func headers(_ params: [String]) {
            var h = header ?? [:]
            for p in params {
                let kv = p.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "") }
                if kv.count == 2 { h[kv[0]] = kv[1] }
            }
            header = h
        }

        func apply(_ c: inout Channel) {
            if let ua { c.ua = ua }
            if let origin { c.origin = origin }
            if let referer { c.referer = referer }
            if let format { c.format = format }
            if let parse { c.parse = parse }
            if let header { c.header = header }
        }
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
