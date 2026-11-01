import Foundation
import JavaScriptCore

/// type 3 + `.js` 站点，对应 quickjs/crawler/Spider.java。
/// 每个站点一个 JSRuntime，首次调用时加载脚本并 init(ext)。
actor JSSpider: SiteAPI {
    let site: Site
    private let runtime: JSRuntime
    private var spider: JSValue?

    /// 同一站点复用一个 JSContext（对应 JsLoader.spiders）；换配置时 reset
    nonisolated(unsafe) private static var cache: [String: JSSpider] = [:]
    private static let lock = NSLock()

    static func shared(_ site: Site) -> JSSpider {
        lock.withLock {
            let key = site.key + "\u{1}" + site.api + "\u{1}" + site.ext
            if let s = cache[key] { return s }
            let s = JSSpider(site: site, runtime: JSRuntime(siteKey: site.key))
            cache[key] = s
            return s
        }
    }

    static func reset() { lock.withLock { cache = [:] } }

    /// 测试用：把外部创建的爬虫登记进缓存
    static func register(_ s: JSSpider) { lock.withLock { cache[s.site.key + "\u{1}" + s.site.api + "\u{1}" + s.site.ext] = s } }

    /// /proxy?do=js&siteKey=… 找到已加载的爬虫
    static func find(_ siteKey: String) -> JSSpider? { lock.withLock { cache.values.first { $0.site.key == siteKey } } }

    init(site: Site, runtime: JSRuntime = JSRuntime()) {
        self.site = site
        self.runtime = runtime
    }

    func home() async throws -> VodResult {
        var r = VodResult.json(try await call("home", [true]) ?? "")
        if r.list.isEmpty, let more = try await call("homeVod", []) { r.list = VodResult.json(more).list }
        return r
    }

    func category(tid: String, page: Int, filter: Bool, extend: [String: String]) async throws -> VodResult {
        VodResult.json(try await call("category", [tid, String(page), filter, extend]) ?? "")
    }

    func detail(ids: [String]) async throws -> VodResult {
        VodResult.json(try await call("detail", [ids.first ?? ""]) ?? "")
    }

    func search(_ key: String, quick: Bool, page: Int) async throws -> VodResult {
        var args: [Any] = [Site.t2s(key), quick]
        if page > 1 { args.append(String(page)) }
        var r = VodResult.json(try await call("search", args) ?? "")
        for i in r.list.indices { r.list[i].siteKey = site.key }
        return r
    }

    func player(flag: String, id: String, vipFlags: [String]) async throws -> VodResult {
        var r = VodResult.json(try await call("play", [flag, id, vipFlags]) ?? "")
        if r.flag.isEmpty { r.flag = flag }
        if r.header.isEmpty { r.header = site.header }
        return r
    }

    /// 直播源内容（对应 Spider.liveContent），返回 m3u / txt 文本
    func live(_ url: String) async throws -> String {
        try await call("live", [url]) ?? ""
    }

    /// 本地代理（对应 Spider.proxyLocal）。返回 (状态码, Content-Type, 内容, 额外响应头)
    /// - 普通：proxy(params) 返回 [code, mime, content, headers?, base64?]
    /// - from=catvod：proxy(url 按 / 拆分的数组, header 对象) 返回 {code, content, buffer, headers}
    func proxy(_ params: [String: String]) async throws -> (Int, String, Data, [String: String]) {
        let obj = try await load()
        if params["from"] == "catvod" {
            let parts = (params["url"] ?? "").components(separatedBy: "/")
            let header = (params["header"]?.data(using: .utf8)).flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [String: Any]()
            let text = try await runtime.call(obj, "proxy", [parts, header]) ?? "{}"
            let o = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
            let headers = (o["headers"] as? [String: Any])?.mapValues { "\($0)" } ?? [:]
            let content = o["content"] as? String ?? ""
            let data = (o["buffer"] as? Int) == 2 ? (JSCrypto.base64(content) ?? Data()) : Data(content.utf8)
            let type = headers.first { $0.key.lowercased() == "content-type" }?.value ?? "application/octet-stream"
            return ((o["code"] as? Int) ?? 200, type, data, headers)
        }
        let text = try await runtime.call(obj, "proxy", [params]) ?? "[]"
        let a = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [Any] ?? []
        let code = a.first.map { AnyJSON(raw: $0).int ?? 500 } ?? 500
        let mime = a.count > 1 ? AnyJSON(raw: a[1]).string : "text/plain"
        var content = a.count > 2 ? AnyJSON(raw: a[2]).string : ""
        let headers = a.count > 3 ? ((a[3] as? [String: Any])?.mapValues { "\($0)" } ?? (AnyJSON(raw: a[3]).string.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } ?? [:])) : [:]
        let base64 = a.count > 4 && AnyJSON(raw: a[4]).int == 1
        if base64, let r = content.range(of: "base64,") { content = String(content[r.upperBound...]) }
        return (code, mime, base64 ? (JSCrypto.base64(content) ?? Data()) : Data(content.utf8), headers)
    }

    // MARK: -

    private func call(_ name: String, _ args: [Any]) async throws -> String? {
        let obj = try await load()
        return try await runtime.call(obj, name, args)
    }

    private func load() async throws -> JSValue {
        if let spider { return spider }
        let api = site.api
        let (obj, cat) = try runtime.perform { () throws -> (JSValue, Bool) in
            let m = try self.runtime.module(api)
            // cat 风格：export function __jsEvalReturn() { return {init, home, …} }，且 req 用 Promise 版 http
            if let f = m.forProperty("__jsEvalReturn"), f.isObject {
                self.runtime.context.setObject(self.runtime.context.objectForKeyedSubscript("http"), forKeyedSubscript: "req" as NSString)
                return (f.call(withArguments: [])!, true)
            }
            if let d = m.forProperty("default"), d.isObject {
                return (d.hasProperty("prototype") && !d.hasProperty("home") ? d.call(withArguments: [])! : d, false)
            }
            // 非模块脚本：写到 globalThis.__JS_SPIDER__
            let g = self.runtime.context.globalObject.forProperty("__JS_SPIDER__")
            guard let g, g.isObject else { throw JSRuntime.Failure.script("脚本没有导出爬虫对象") }
            return (g, false)
        }
        _ = try await runtime.call(obj, "init", [cat ? cfg() : ext()])
        spider = obj
        return obj
    }

    /// 非 cat 风格：ext 是 JSON 对象时按对象传入
    private func ext() -> Any {
        guard let d = site.ext.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d), o is [String: Any] else { return site.ext }
        return o
    }

    private func cfg() -> [String: Any] {
        ["stype": 3, "skey": site.key, "ext": ext()]
    }
}
