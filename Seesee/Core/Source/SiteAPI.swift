import Foundation

protocol SiteAPI: Sendable {
    func home() async throws -> VodResult
    func category(tid: String, page: Int, filter: Bool, extend: [String: String]) async throws -> VodResult
    func detail(ids: [String]) async throws -> VodResult
    func search(_ key: String, quick: Bool, page: Int) async throws -> VodResult
    func player(flag: String, id: String, vipFlags: [String]) async throws -> VodResult
}

enum SourceError: LocalizedError {
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let api): "iOS 不支持此站点类型：\(api)"
        }
    }
}

func makeAPI(_ site: Site, fetch: @escaping HTTP.Fetch = HTTP.live) -> SiteAPI {
    switch site.type {
    case 0, 1, 2: CMSSource(site: site, fetch: fetch)
    case 4: CustomSource(site: site, fetch: fetch)
    case 3 where site.api.contains(".js"): JSSpider.shared(site)
    default: Unsupported(api: site.api)
    }
}

struct Unsupported: SiteAPI {
    let api: String
    func home() async throws -> VodResult { throw SourceError.unsupported(api) }
    func category(tid: String, page: Int, filter: Bool, extend: [String: String]) async throws -> VodResult { throw SourceError.unsupported(api) }
    func detail(ids: [String]) async throws -> VodResult { throw SourceError.unsupported(api) }
    func search(_ key: String, quick: Bool, page: Int) async throws -> VodResult { throw SourceError.unsupported(api) }
    func player(flag: String, id: String, vipFlags: [String]) async throws -> VodResult { throw SourceError.unsupported(api) }
}

/// type 0/1/2/4 共用的请求方式：ext 非空时带 extend，ext > 1000 字走 POST（对应 SiteViewModel.call）
extension Site {
    func call(_ params: [(String, String)], ext: String? = nil, fetch: HTTP.Fetch) async throws -> String {
        let ext = ext ?? self.ext
        var params = params
        if !ext.isEmpty {
            params.removeAll { $0.0 == "extend" }
            params.append(("extend", ext))
        }
        let t = TimeInterval(timeout)
        let req = ext.count <= 1000
            ? try HTTP.get(api, query: params, headers: header, timeout: t)
            : try HTTP.post(api, form: params, headers: header, timeout: t)
        return HTTP.string(try await fetch(req))
    }

    /// 关键词繁转简（对应 Trans.t2s）
    static func t2s(_ s: String) -> String {
        s.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? s
    }
}

extension Dictionary where Key == String, Value == String {
    /// 稳定排序的 JSON，便于缓存与测试
    var sortedJSON: String {
        let d = (try? JSONSerialization.data(withJSONObject: self, options: [.sortedKeys])) ?? Data("{}".utf8)
        return HTTP.string(d)
    }
}
