import Foundation

/// 配置里的 `proxy` 与 `hosts`（对应 OkProxySelector / OkDns）
/// - proxy：`[{name, hosts: [域名片段或正则], urls: ["http://h:p", "socks5://h:p"]}]`，命中的请求走该代理
/// - hosts：`["旧域名=新域名"]`。URLSession 不能换 DNS，这里改写 URL 的 host 并带上原 Host 头；
///   ponytail: HTTPS 下证书/SNI 仍按新域名校验，只对新域名证书也覆盖旧域名或明文 HTTP 的场景有效
enum NetRules {
    struct ProxyRule: Decodable {
        var hosts: [String] = []
        var urls: [String] = []
    }

    nonisolated(unsafe) static var proxies: [ProxyRule] = [] { didSet { sessions = [:] } }
    nonisolated(unsafe) static var hosts: [(from: String, to: String)] = []
    nonisolated(unsafe) private static var sessions: [String: URLSession] = [:]
    private static let lock = NSLock()

    static func configure(proxy: [ProxyRule], hosts: [String]) {
        lock.withLock {
            proxies = proxy
            self.hosts = hosts.compactMap { h in
                let p = h.split(separator: "=", maxSplits: 1).map(String.init)
                return p.count == 2 && !p[0].isEmpty ? (p[0], p[1]) : nil
            }
        }
    }

    /// 与 Util.containOrMatch 一致：包含或整串正则匹配
    static func match(_ host: String, _ rule: String) -> Bool {
        host.contains(rule) || (try? Regex(rule)).map { host.wholeMatch(of: $0) != nil } == true
    }

    /// 改写 hosts，返回新请求（原 host 写入 Host 头）
    static func rewrite(_ req: URLRequest) -> URLRequest {
        guard let url = req.url, let host = url.host, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return req }
        let rules = lock.withLock { hosts }
        guard let to = rules.first(where: { match(host, $0.from) })?.to else { return req }
        comps.host = to
        guard let u = comps.url else { return req }
        var r = req
        r.url = u
        if r.value(forHTTPHeaderField: "Host") == nil { r.setValue(host, forHTTPHeaderField: "Host") }
        return r
    }

    /// 该地址应使用的 session：命中 proxy 规则时用带代理的 session
    static func session(for url: URL?, default base: URLSession = .shared) -> URLSession {
        guard let host = url?.host, host != "127.0.0.1" else { return base }
        return lock.withLock {
            guard let rule = proxies.first(where: { $0.hosts.contains { match(host, $0) } }),
                  let raw = rule.urls.first, let p = URLComponents(string: raw), let ph = p.host, let port = p.port else { return base }
            if let s = sessions[raw] { return s }
            let c = URLSessionConfiguration.default
            c.connectionProxyDictionary = (p.scheme ?? "").hasPrefix("socks")
                ? [kCFStreamPropertySOCKSProxyHost: ph, kCFStreamPropertySOCKSProxyPort: port]
                : ["HTTPEnable": 1, "HTTPProxy": ph, "HTTPPort": port, "HTTPSEnable": 1, "HTTPSProxy": ph, "HTTPSPort": port]
            let s = URLSession(configuration: c)
            sessions[raw] = s
            return s
        }
    }
}
