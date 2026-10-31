import Foundation

struct SearchHit: Sendable {
    let site: Site
    let result: VodResult
}

/// 多站并发搜索：最多 limit 个站同时请求，有结果的站按返回先后逐个产出；单站失败忽略
enum SearchRunner {
    static func run(_ keyword: String, sites: [Site], quick: Bool, limit: Int = 5,
                    api: @escaping @Sendable (Site) -> SiteAPI) -> AsyncStream<SearchHit> {
        let sites = sites.filter { $0.isSupported && (!quick || $0.quickSearch == 1) }
        return AsyncStream { cont in
            let task = Task {
                await withTaskGroup(of: SearchHit?.self) { group in
                    var next = 0
                    func add() {
                        guard next < sites.count else { return }
                        let site = sites[next]
                        next += 1
                        group.addTask {
                            guard var r = try? await api(site).search(keyword, quick: quick, page: 1), !r.list.isEmpty else { return nil }
                            for i in r.list.indices { r.list[i].siteKey = site.key }
                            return SearchHit(site: site, result: r)
                        }
                    }
                    for _ in 0..<limit { add() }
                    for await hit in group {
                        if let hit { cont.yield(hit) }
                        add()
                    }
                }
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}
