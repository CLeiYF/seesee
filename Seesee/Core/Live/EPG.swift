import Foundation

/// 节目单条目
struct Programme: Hashable, Identifiable {
    var title: String
    var start: Date
    var end: Date
    var id: Date { start }

    func isLive(_ now: Date = Date()) -> Bool { start <= now && now <= end }
    func isPast(_ now: Date = Date()) -> Bool { end < now }
}

/// EPG：按频道查询的 JSON 接口（{date} 替换为当天）与 xmltv（含 .gz）
enum EPG {
    /// JSON：{ "date": "2024-01-01", "epg_data": [{ "title", "start": "HH:mm", "end": "HH:mm" }] }；也可能直接返回 xmltv
    static func parse(_ text: String, date: Date = Date(), timeZone: TimeZone = .current) -> [Programme] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("<") { return XMLTV.parse(Data(t.utf8), timeZone: timeZone).values.first ?? [] }
        guard let d = t.data(using: .utf8), let obj = (try? JSONDecoder().decode(AnyJSON.self, from: d))?.value as? [String: Any],
              let list = obj["epg_data"] as? [[String: Any]] else { return [] }
        let day = (obj["date"] as? String).flatMap { dayFormatter(timeZone).date(from: $0) } ?? Calendar.current.startOfDay(for: date)
        var out: [Programme] = []
        for item in list {
            guard let title = item["title"] as? String,
                  let s = clock(item["start"] as? String, on: day, timeZone),
                  var e = clock(item["end"] as? String, on: day, timeZone) else { continue }
            if e < s { e = e.addingTimeInterval(86400) } // 跨零点
            let p = Programme(title: title, start: s, end: e)
            if !out.contains(p) { out.append(p) }
        }
        return out.sorted { $0.start < $1.start }
    }

    static func url(_ template: String, date: Date = Date(), timeZone: TimeZone = .current) -> String {
        template.replacingOccurrences(of: "{date}", with: dayFormatter(timeZone).string(from: date))
    }

    static func dayFormatter(_ tz: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    private static func clock(_ hm: String?, on day: Date, _ tz: TimeZone) -> Date? {
        guard let p = hm?.split(separator: ":"), p.count >= 2, let h = Int(p[0]), let m = Int(p[1]) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(bySettingHour: h, minute: m, second: 0, of: day)
    }
}

/// xmltv：<tv><channel id><display-name/></channel><programme start stop channel><title/></programme></tv>
/// 返回 key → 节目，key 同时登记 channel id 与所有 display-name，方便按 tvg-id 或频道名查
final class XMLTV: NSObject, XMLParserDelegate {
    private var names: [String: [String]] = [:]
    private var programmes: [String: [Programme]] = [:]
    private var channelId = ""
    private var current: (channel: String, start: Date, end: Date)?
    private var text = ""
    private let fmt: DateFormatter

    private init(timeZone: TimeZone) {
        fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = timeZone
        fmt.dateFormat = "yyyyMMddHHmmss Z"
    }

    static func parse(_ data: Data, timeZone: TimeZone = .current) -> [String: [Programme]] {
        let x = XMLTV(timeZone: timeZone)
        let p = XMLParser(data: data)
        p.delegate = x
        p.parse()
        var out: [String: [Programme]] = [:]
        for (id, list) in x.programmes {
            let sorted = list.sorted { $0.start < $1.start }
            out[id] = sorted
            for n in x.names[id] ?? [] where out[n] == nil { out[n] = sorted }
        }
        return out
    }

    /// `20240101083000 +0800`，没有时区后缀时按配置时区
    private func date(_ s: String?) -> Date? {
        guard let t = s?.trimmingCharacters(in: .whitespaces), t.count >= 14 else { return nil }
        if let d = fmt.date(from: t) { return d }
        let plain = DateFormatter()
        plain.locale = fmt.locale
        plain.timeZone = fmt.timeZone
        plain.dateFormat = "yyyyMMddHHmmss"
        return plain.date(from: String(t.prefix(14)))
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        text = ""
        switch name {
        case "channel": channelId = a["id"] ?? ""
        case "programme":
            if let s = date(a["start"]), let e = date(a["stop"]) { current = (a["channel"] ?? "", s, e) } else { current = nil }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) { text += s }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "display-name" where !channelId.isEmpty && !t.isEmpty: names[channelId, default: []].append(t)
        case "channel": channelId = ""
        case "title":
            if let c = current, !t.isEmpty { programmes[c.channel, default: []].append(Programme(title: t, start: c.start, end: c.end)) }
        case "programme": current = nil
        default: break
        }
        text = ""
    }
}

extension Data {
    /// gzip 解压（xmltv.xml.gz）
    var gunzipped: Data? {
        guard count > 18, self[startIndex] == 0x1f, self[startIndex + 1] == 0x8b else { return nil }
        // 跳过 gzip 头（10 字节 + 可选字段），去掉 8 字节尾，剩下的是 raw DEFLATE（NSData .zlib 即 raw deflate）
        var offset = 10
        let flags = self[startIndex + 3]
        if flags & 0x04 != 0, count > offset + 2 { offset += 2 + (Int(self[startIndex + offset]) | Int(self[startIndex + offset + 1]) << 8) }
        if flags & 0x08 != 0, let z = self[(startIndex + offset)...].firstIndex(of: 0) { offset = z - startIndex + 1 }
        if flags & 0x10 != 0, let z = self[(startIndex + offset)...].firstIndex(of: 0) { offset = z - startIndex + 1 }
        if flags & 0x02 != 0 { offset += 2 }
        let deflate = self[(startIndex + offset)..<(endIndex - 8)]
        return try? (Data(deflate) as NSData).decompressed(using: .zlib) as Data
    }
}
