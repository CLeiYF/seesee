import Foundation

enum HTTP {
    typealias Fetch = @Sendable (URLRequest) async throws -> Data

    static let chrome = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"

    /// 安卓版 OkHttp 的默认 UA（letmeseesee 用 okhttp 5.0.0-alpha.14）。
    /// 不少配置服务器按 UA 分流：okhttp/ 开头才返回 JSON，浏览器 UA 会被 302 到网页（如 itv.mangzhexuexi.com）
    static let okhttp = "okhttp/5.0.0-alpha.14"

    /// 默认 UA：与安卓一致用 okhttp，仅 gitcode.net 用 Chrome（对应 RequestInterceptor）
    static func defaultUA(host: String) -> String {
        host.contains("gitcode.net") ? chrome : okhttp
    }

    /// 配置里的 `headers`：host 包含或正则匹配时注入
    nonisolated(unsafe) static var hostHeaders: [HostHeader] = []

    static let live: Fetch = { request in
        let request = NetRules.rewrite(request)
        let (data, response) = try await NetRules.session(for: request.url).data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    static func get(_ url: String, query: [(String, String)] = [], headers: [String: String] = [:], timeout: TimeInterval = 15) throws -> URLRequest {
        guard var comps = URLComponents(string: url.trimmingCharacters(in: .whitespaces)) else { throw URLError(.badURL) }
        if !query.isEmpty {
            comps.percentEncodedQueryItems = (comps.percentEncodedQueryItems ?? []) + query.map { URLQueryItem(name: encode($0.0), value: encode($0.1)) }
        }
        guard let u = comps.url else { throw URLError(.badURL) }
        return request(u, headers: headers, timeout: timeout)
    }

    static func post(_ url: String, form: [(String, String)], headers: [String: String] = [:], timeout: TimeInterval = 15) throws -> URLRequest {
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        var req = request(u, headers: headers, timeout: timeout)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&").data(using: .utf8)
        return req
    }

    /// 默认 UA + 配置 headers + 调用方 headers（后者优先）
    static func request(_ url: URL, headers: [String: String], timeout: TimeInterval) -> URLRequest {
        // 配置/直播源/EPG 会随时更新，不用 URLCache 的启发式缓存（服务器没给 Cache-Control 时也会被缓存）
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        let host = url.host?.lowercased() ?? ""
        req.setValue(defaultUA(host: host), forHTTPHeaderField: "User-Agent")
        for item in hostHeaders where item.matches(host) {
            item.header.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        }
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        return req
    }

    /// 与 OkHttp 一致：保留 RFC 3986 unreserved，其余全部编码
    static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? s
    }

    static func string(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}

struct HostHeader: Decodable {
    let host: String
    let header: [String: String]

    func matches(_ value: String) -> Bool {
        value.contains(host) || (try? Regex(host)).map { value.contains($0) } == true
    }
}
