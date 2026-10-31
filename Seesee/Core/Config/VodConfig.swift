import Foundation

struct Parse: Decodable, Hashable {
    var name = ""
    var type = 0
    var url = ""
    var flag: [String] = []
    var header: [String: String] = [:]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        name = c.str(AnyKey("name"))
        type = c.int(AnyKey("type")) ?? 0
        url = c.str(AnyKey("url"))
        if let ext = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("ext")) {
            flag = ext.list(AnyKey("flag"))
            header = ext.dict(AnyKey("header"))
        }
    }
}

struct Depot: Decodable, Hashable {
    var name = ""
    var url = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        name = c.str(AnyKey("name"))
        url = c.str(AnyKey("url"))
    }
}

/// 点播配置（对应 VodConfig.java）；lives 留给 M5
struct VodConfig: Decodable {
    var spider = ""
    var wallpaper = ""
    var logo = ""
    var notice = ""
    var sites: [Site] = []
    var parses: [Parse] = []
    var flags: [String] = []
    var headers: [HostHeader] = []
    var urls: [Depot] = []
    var msg = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        spider = c.str(AnyKey("spider"))
        wallpaper = c.str(AnyKey("wallpaper"))
        logo = c.str(AnyKey("logo"))
        notice = c.str(AnyKey("notice"))
        sites = c.list(AnyKey("sites"))
        // `video` 对象里也可能放 sites
        if let video = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("video")) {
            sites += video.list(AnyKey("sites"))
        }
        parses = c.list(AnyKey("parses"))
        flags = c.list(AnyKey("flags"))
        headers = c.list(AnyKey("headers"))
        urls = c.list(AnyKey("urls"))
        msg = c.str(AnyKey("msg"))
        var seen = Set<String>()
        sites = sites.filter { !$0.key.isEmpty && seen.insert($0.key).inserted }
        for i in sites.indices where sites[i].jar.isEmpty { sites[i].jar = spider }
    }

    static func parse(_ text: String) throws -> VodConfig {
        try JSONDecoder().decode(VodConfig.self, from: Data(text.utf8))
    }

    /// 首页可选站点：未隐藏且 iOS 能跑
    var homeSites: [Site] { sites.filter { $0.hide == 0 } }
}

enum ConfigLoader {
    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { m } else { nil } }
    }

    /// 拉取并解码；遇到多仓库（urls）时跟进第一个仓库，返回最终 URL、解码文本与配置
    static func load(_ url: String, fetch: HTTP.Fetch, depth: Int = 0) async throws -> (url: String, text: String, config: VodConfig, depots: [Depot]) {
        let raw = HTTP.string(try await fetch(try HTTP.get(url)))
        return try await resolve(url, raw: raw, fetch: fetch, depth: depth)
    }

    /// 已拿到原始文本（如本地文件导入）时直接解码
    static func resolve(_ url: String, raw: String, fetch: HTTP.Fetch, depth: Int = 0) async throws -> (url: String, text: String, config: VodConfig, depots: [Depot]) {
        let text = try ConfigDecoder.verify(url: url, data: raw)
        let config = try VodConfig.parse(text)
        if !config.msg.isEmpty, config.sites.isEmpty { throw Failure.message(config.msg) }
        if let first = config.urls.first, config.sites.isEmpty, depth < 3 {
            let next = try await load(first.url, fetch: fetch, depth: depth + 1)
            return (next.url, next.text, next.config, config.urls)
        }
        return (url, text, config, [])
    }
}
