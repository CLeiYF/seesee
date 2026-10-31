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
            let s = JSSpider(site: site)
            cache[key] = s
            return s
        }
    }

    static func reset() { lock.withLock { cache = [:] } }

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
