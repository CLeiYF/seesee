import Foundation

/// type 4 自定义接口：ext 可以是 URL（首次使用时拉取内容替换），结果统一为 JSON
actor CustomSource: SiteAPI {
    let site: Site
    let fetch: HTTP.Fetch
    private var resolvedExt: String?

    init(site: Site, fetch: @escaping HTTP.Fetch) {
        self.site = site
        self.fetch = fetch
    }

    func home() async throws -> VodResult {
        VodResult.json(try await call([("filter", "true")]))
    }

    func category(tid: String, page: Int, filter: Bool, extend: [String: String]) async throws -> VodResult {
        let ext = Data(extend.sortedJSON.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        return VodResult.json(try await call([("ext", ext), ("ac", "detail"), ("t", tid), ("pg", String(page))]))
    }

    func detail(ids: [String]) async throws -> VodResult {
        VodResult.json(try await call([("ac", "detail"), ("ids", ids.joined(separator: ","))]))
    }

    func search(_ key: String, quick: Bool, page: Int) async throws -> VodResult {
        var params = [("wd", Site.t2s(key)), ("quick", String(quick)), ("extend", "")]
        if page > 1 { params.append(("pg", String(page))) }
        var result = VodResult.json(try await call(params))
        for i in result.list.indices { result.list[i].siteKey = site.key }
        return result
    }

    func player(flag: String, id: String, vipFlags: [String]) async throws -> VodResult {
        var result = VodResult.json(try await call([("play", id), ("flag", flag)]))
        if result.flag.isEmpty { result.flag = flag }
        if result.header.isEmpty { result.header = site.header }
        return result
    }

    private func call(_ params: [(String, String)]) async throws -> String {
        try await site.call(params, ext: try await ext(), fetch: fetch)
    }

    private func ext() async throws -> String {
        if let resolvedExt { return resolvedExt }
        var ext = site.ext
        if ext.hasPrefix("http") {
            let text = HTTP.string(try await fetch(try HTTP.get(ext)))
            if !text.isEmpty { ext = text }
        }
        resolvedExt = ext
        return ext
    }
}
