import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppState {
    var configURL = ""
    var config = VodConfig()
    var depots: [Depot] = []
    var home: Site?
    var loading = false
    var error: String?
    var notice: String?

    @ObservationIgnored let fetch: HTTP.Fetch

    init(fetch: @escaping HTTP.Fetch = HTTP.live) {
        self.fetch = fetch
    }

    func api(_ site: Site) -> SiteAPI { makeAPI(site, fetch: fetch) }

    func site(_ key: String) -> Site? { config.sites.first { $0.key == key } }

    /// 启动时恢复最近一次使用的配置
    func restore(_ context: ModelContext) async {
        // ponytail: 启动参数 `-config <url>` 直接加载，便于模拟器调试
        if configURL.isEmpty, let url = UserDefaults.standard.string(forKey: "config") {
            return await load(url, context: context)
        }
        var d = FetchDescriptor<ConfigRecord>(sortBy: [SortDescriptor(\.time, order: .reverse)])
        d.fetchLimit = 1
        guard configURL.isEmpty, let last = try? context.fetch(d).first else { return }
        await load(last.url, context: context)
    }

    func load(_ url: String, raw: String? = nil, context: ModelContext) async {
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        loading = true
        error = nil
        defer { loading = false }
        let record = record(url, context)
        do {
            let result = if let raw {
                try await ConfigLoader.resolve(url, raw: raw, fetch: fetch)
            } else {
                try await ConfigLoader.load(url, fetch: fetch)
            }
            apply(result.config, url: url, home: record?.home)
            depots = result.depots
            notice = result.config.notice.isEmpty ? nil : result.config.notice
            save(url, text: result.text, context)
        } catch let e {
            // 网络失败时用上次缓存的文本
            if let record, !record.text.isEmpty, let cached = try? VodConfig.parse(record.text) {
                apply(cached, url: url, home: record.home)
                error = "配置加载失败，已使用缓存：\(e.localizedDescription)"
            } else {
                error = "配置加载失败：\(e.localizedDescription)"
            }
        }
    }

    func setHome(_ site: Site, context: ModelContext) {
        home = site
        record(configURL, context)?.home = site.key
        try? context.save()
    }

    private func apply(_ config: VodConfig, url: String, home key: String?) {
        self.config = config
        configURL = url
        HTTP.hostHeaders = config.headers
        let usable = config.homeSites.filter(\.isSupported)
        home = usable.first { $0.key == key } ?? usable.first
    }

    private func record(_ url: String, _ context: ModelContext) -> ConfigRecord? {
        try? context.fetch(FetchDescriptor<ConfigRecord>(predicate: #Predicate { $0.url == url })).first
    }

    private func save(_ url: String, text: String, _ context: ModelContext) {
        if let r = record(url, context) {
            r.text = text
            r.time = .now
        } else {
            context.insert(ConfigRecord(url: url, text: text, home: home?.key ?? ""))
        }
        try? context.save()
    }
}
