import Foundation
import Observation

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
    /// 当前 tab；`msearch:` 影片点击后切到搜索
    var tab = UserDefaults.standard.integer(forKey: "tab")
    /// 待执行的搜索词（由 msearch 等跳转写入，SearchView 消费后清空）
    var pendingSearch: String?

    let library: Library
    @ObservationIgnored let fetch: HTTP.Fetch

    init(library: Library? = nil, fetch: @escaping HTTP.Fetch = HTTP.live) {
        self.library = library ?? Library()
        self.fetch = fetch
    }

    func api(_ site: Site) -> SiteAPI { makeAPI(site, fetch: fetch) }

    func site(_ key: String) -> Site? { config.sites.first { $0.key == key } }

    /// 参与搜索的站点（配置 searchable 且用户未关闭）
    var searchSites: [Site] { config.sites.filter { $0.isSupported && library.isSearchable($0) } }

    /// 启动时恢复最近一次使用的配置
    func restore() async {
        guard configURL.isEmpty else { return }
        // ponytail: 启动参数 `-config <url>` 直接加载，便于模拟器调试
        if let url = UserDefaults.standard.string(forKey: "config") { return await load(url) }
        if let last = library.data.configs.first { await load(last.url) }
    }

    func load(_ url: String, raw: String? = nil) async {
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        loading = true
        error = nil
        defer { loading = false }
        let saved = library.config(url)
        do {
            let result = if let raw {
                try await ConfigLoader.resolve(url, raw: raw, fetch: fetch)
            } else {
                try await ConfigLoader.load(url, fetch: fetch)
            }
            library.saveConfig(url: url, text: result.text)
            apply(result.config, url: url, home: saved?.home)
            depots = result.depots
            notice = result.config.notice.isEmpty ? nil : result.config.notice
        } catch let e {
            // 网络失败时用上次缓存的文本
            if let saved, !saved.text.isEmpty, let cached = try? VodConfig.parse(saved.text) {
                apply(cached, url: url, home: saved.home)
                error = "配置加载失败，已使用缓存：\(e.localizedDescription)"
            } else {
                error = "配置加载失败：\(e.localizedDescription)"
            }
        }
    }

    func setHome(_ site: Site) {
        home = site
        library.setHome(url: configURL, key: site.key)
    }

    private func apply(_ config: VodConfig, url: String, home key: String?) {
        if configURL != url { JSSpider.reset() }
        self.config = config
        configURL = url
        HTTP.hostHeaders = config.headers
        Sniffer.rules = config.rules
        Sniffer.ads = config.ads
        let usable = config.homeSites.filter(\.isSupported)
        home = usable.first { $0.key == key } ?? usable.first
    }
}
