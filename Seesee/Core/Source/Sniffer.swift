import Foundation

/// 配置里的 rules：按 host 指定嗅探正则、排除项和页面加载后执行的脚本
struct SniffRule: Decodable, Hashable {
    var name = ""
    var hosts: [String] = []
    var regex: [String] = []
    var script: [String] = []
    var exclude: [String] = []

    init(hosts: [String] = [], regex: [String] = [], script: [String] = [], exclude: [String] = []) {
        (self.hosts, self.regex, self.script, self.exclude) = (hosts, regex, script, exclude)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        name = c.str(AnyKey("name"))
        hosts = c.list(AnyKey("hosts"))
        regex = c.list(AnyKey("regex"))
        script = c.list(AnyKey("script"))
        exclude = c.list(AnyKey("exclude"))
    }
}

/// 对应 utils/Sniffer
enum Sniffer {
    nonisolated(unsafe) static var rules: [SniffRule] = []
    nonisolated(unsafe) static var ads: [String] = []

    static func isVideoFormat(_ url: String) -> Bool {
        let rule = rule(for: url)
        for e in rule.exclude where contains(url, e) { return false }
        for r in rule.regex where contains(url, r) { return true }
        if url.contains("url=http") || url.contains("v=http") || url.contains(".html") { return false }
        let sniffer = #/https?://[^\s]{12,}\.(?:m3u8|mp4|mkv|flv|mp3|m4a|aac|mpd)(?:\?.*)?|https?://.*?video/tos[^\s]*|rtmp:[^\s]+/#
        return url.contains(sniffer)
    }

    /// 页面加载完成后要执行的脚本
    static func scripts(for url: String) -> [String] { rule(for: url).script }

    static func isAd(_ host: String) -> Bool { ads.contains { matches(host, $0) } }

    /// 用 url 自身的 host 与其 `url=` 参数里的 host 匹配规则
    static func rule(for url: String) -> SniffRule {
        let c = URLComponents(string: url)
        guard let host = c?.host?.lowercased() else { return SniffRule() }
        let inner = c?.queryItems?.first { $0.name == "url" }?.value.flatMap { URLComponents(string: $0)?.host?.lowercased() } ?? ""
        let hosts = "\(host),\(inner)"
        return rules.first { $0.hosts.contains { matches(hosts, $0) } } ?? SniffRule()
    }

    /// 对应 Util.containOrMatch：包含或整串正则匹配
    static func matches(_ text: String, _ pattern: String) -> Bool {
        text.contains(pattern) || ((try? Regex(pattern)).map { text.wholeMatch(of: $0) != nil } ?? false)
    }

    /// 包含或正则查找
    private static func contains(_ text: String, _ pattern: String) -> Bool {
        text.contains(pattern) || ((try? Regex(pattern)).map { text.contains($0) } ?? false)
    }
}
