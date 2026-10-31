import Foundation

/// type 0（XML）/ 1 / 2（JSON）苹果 CMS 接口，对应 SiteViewModel 的非 spider 分支
struct CMSSource: SiteAPI {
    let site: Site
    let fetch: HTTP.Fetch

    private var ac: String { site.type == 0 ? "videolist" : "detail" }

    func home() async throws -> VodResult {
        let req = try HTTP.get(site.api, headers: site.header, timeout: TimeInterval(site.timeout))
        let text = HTTP.string(try await fetch(req))
        return try await fetchPic(VodResult.from(type: site.type, text))
    }

    func category(tid: String, page: Int, filter: Bool, extend: [String: String]) async throws -> VodResult {
        var params: [(String, String)] = []
        if site.type == 1, !extend.isEmpty { params.append(("f", extend.sortedJSON)) }
        params += [("ac", ac), ("t", tid), ("pg", String(page))]
        return VodResult.from(type: site.type, try await site.call(params, fetch: fetch))
    }

    func detail(ids: [String]) async throws -> VodResult {
        let text = try await site.call([("ac", ac), ("ids", ids.joined(separator: ","))], fetch: fetch)
        return VodResult.from(type: site.type, text)
    }

    func search(_ key: String, quick: Bool, page: Int) async throws -> VodResult {
        var params = [("wd", Site.t2s(key)), ("quick", String(quick)), ("extend", "")]
        if page > 1 { params.append(("pg", String(page))) }
        let text = try await site.call(params, fetch: fetch)
        var result = try await fetchPic(VodResult.from(type: site.type, text))
        for i in result.list.indices { result.list[i].siteKey = site.key }
        return result
    }

    func player(flag: String, id: String, vipFlags: [String]) async throws -> VodResult {
        var result = VodResult()
        result.url = PlayURL(id)
        result.flag = flag
        result.header = site.header
        result.playUrl = site.playUrl
        result.parse = Sniffer.isVideoFormat(id) && site.playUrl.isEmpty ? 0 : 1
        return result
    }

    /// 列表无图时按 ids 回查详情补图；配置了 categories 时只保留这些分类
    private func fetchPic(_ result: VodResult) async throws -> VodResult {
        guard let first = result.list.first, first.vodPic.isEmpty else { return result }
        let items = site.categories.isEmpty ? result.list : result.list.filter { site.categories.contains($0.typeName) }
        var result = result
        guard !items.isEmpty else {
            result.list = []
            return result
        }
        let req = try HTTP.get(site.api, query: [("ac", ac), ("ids", items.map(\.vodId).joined(separator: ","))], headers: site.header, timeout: TimeInterval(site.timeout))
        result.list = VodResult.from(type: site.type, HTTP.string(try await fetch(req))).list
        return result
    }
}
