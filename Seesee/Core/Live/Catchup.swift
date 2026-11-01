import Foundation

/// 回看（对应 bean/Catchup）：
/// - type=append：按 replace 改写地址后追加 source
/// - type=default：source 本身就是完整地址
/// source 占位符：${(b)yyyyMMddHHmmss} / ${(e)…} / {utc:…} / {utcend:…}
struct Catchup: Decodable, Hashable {
    var type = ""
    var days = ""
    var regex = ""
    var source = ""
    var replace = ""

    init(type: String = "", days: String = "", regex: String = "", source: String = "", replace: String = "") {
        (self.type, self.days, self.regex, self.source, self.replace) = (type, days, regex, source, replace)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        type = c.str(AnyKey("type"))
        days = c.str(AnyKey("days"))
        regex = c.str(AnyKey("regex"))
        source = c.str(AnyKey("source"))
        replace = c.str(AnyKey("replace"))
    }

    /// 从 m3u 行的 catchup= / catchup-source= / catchup-replace= 读取；没有 source 视为无回看
    static func from(attrs line: String) -> Catchup? {
        let c = Catchup(type: LiveParser.attr(line, "catchup"), days: LiveParser.attr(line, "catchup-days"),
                        source: LiveParser.attr(line, "catchup-source"), replace: LiveParser.attr(line, "catchup-replace"))
        return c.source.isEmpty ? nil : c
    }

    func url(_ url: String, start: Date, end: Date, timeZone: TimeZone = .current) -> String {
        var result = source
        for m in source.matches(of: #/\$?\{([^}]+)\}/#) {
            result = result.replacingOccurrences(of: String(m.output.0), with: value(String(m.output.1), start, end, timeZone))
        }
        if type == "default" { return result }
        var base = url
        let parts = replace.split(separator: ",", maxSplits: 1).map(String.init)
        if parts.count == 2, let r = try? Regex(parts[0]) { base = base.replacing(r, with: parts[1]) }
        if URLComponents(string: base)?.query?.isEmpty == false { result = result.replacingOccurrences(of: "?", with: "&") }
        return base + result
    }

    private func value(_ tag: String, _ start: Date, _ end: Date, _ tz: TimeZone) -> String {
        func fmt(_ d: Date, _ pattern: String) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = tz
            f.dateFormat = pattern
            return f.string(from: d)
        }
        if tag.hasPrefix("(b)") { return fmt(start, String(tag.dropFirst(3))) }
        if tag.hasPrefix("(e)") { return fmt(end, String(tag.dropFirst(3))) }
        if tag.hasPrefix("utcend") { return String(Int(end.timeIntervalSince1970)) }
        if tag.hasPrefix("utc") { return String(Int(start.timeIntervalSince1970)) }
        if tag == "timestamp" { return String(Int(Date().timeIntervalSince1970)) }
        return ""
    }
}
