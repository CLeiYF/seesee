import Foundation

protocol SiteAPI: Sendable {
    func home() async throws -> VodResult
    func category(tid: String, page: Int, filter: Bool, extend: [String: String]) async throws -> VodResult
    func detail(ids: [String]) async throws -> VodResult
    func search(_ key: String, quick: Bool, page: Int) async throws -> VodResult
    func player(flag: String, id: String, vipFlags: [String]) async throws -> VodResult
    /// 播放状态回调（start/progress/pause/stop，毫秒），供爬虫做播放回传（如 csp_Emby）
    func report(_ state: String, positionMs: Int) async
}

extension SiteAPI {
    func report(_ state: String, positionMs: Int) async {}
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
    case 3: bundled(site)
    default: Unsupported(api: site.api)
    }
}

/// csp_Xxx：按候选顺序（外接仓库 → 内置）改写 api 后按 JS 爬虫运行
private func bundled(_ site: Site) -> SiteAPI {
    let candidates = Site.spiderCandidates(site.api)
    guard !candidates.isEmpty else { return Unsupported(api: site.api) }
    return FallbackSpider(spiders: candidates.map { var s = site; s.api = $0; return JSSpider.shared(s) })
}

/// 依次尝试多个实现：当前的加载失败（如仓库里没有这个文件）就换下一个，成功后固定使用
actor FallbackSpider: SiteAPI {
    private var spiders: [SiteAPI]

    init(spiders: [SiteAPI]) { self.spiders = spiders }

    private func run(_ body: (SiteAPI) async throws -> VodResult) async throws -> VodResult {
        var last: Error = SourceError.unsupported("")
        while let s = spiders.first {
            do { return try await body(s) } catch {
                last = error
                // ponytail: 任何错误都换下一个；只剩最后一个时保留，避免网络抖动后彻底不可用
                guard spiders.count > 1 else { break }
                spiders.removeFirst()
            }
        }
        throw last
    }

    func home() async throws -> VodResult { try await run { try await $0.home() } }
    func category(tid: String, page: Int, filter: Bool, extend: [String: String]) async throws -> VodResult {
        try await run { try await $0.category(tid: tid, page: page, filter: filter, extend: extend) }
    }
    func detail(ids: [String]) async throws -> VodResult { try await run { try await $0.detail(ids: ids) } }
    func search(_ key: String, quick: Bool, page: Int) async throws -> VodResult { try await run { try await $0.search(key, quick: quick, page: page) } }
    func player(flag: String, id: String, vipFlags: [String]) async throws -> VodResult {
        try await run { try await $0.player(flag: flag, id: id, vipFlags: vipFlags) }
    }
    func report(_ state: String, positionMs: Int) async { await spiders.first?.report(state, positionMs: positionMs) }
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
