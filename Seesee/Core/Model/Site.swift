import Foundation

struct Style: Codable, Hashable {
    var type = "rect"
    var ratio: Double = 0

    var effectiveRatio: Double { ratio <= 0 ? (type == "oval" ? 1 : 0.75) : min(4, ratio) }

    init(type: String = "rect", ratio: Double = 0) {
        self.type = type.isEmpty ? "rect" : type
        self.ratio = ratio
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.init(type: c.str(AnyKey("type")), ratio: c.double(AnyKey("ratio")) ?? 0)
    }

    /// 对应 Style.get(land, circle, ratio)
    static func from(land: Int, circle: Int, ratio: Double) -> Style? {
        if land == 1 { return Style(type: "rect", ratio: ratio == 0 ? 1.33 : ratio) }
        if circle == 1 { return Style(type: "oval", ratio: ratio == 0 ? 1 : ratio) }
        return nil
    }
}

struct Site: Decodable, Hashable, Identifiable {
    var key = ""
    var name = ""
    var api = ""
    var ext = ""
    var jar = ""
    var playUrl = ""
    var type = 0
    var hide = 0
    var timeout = 15
    var searchable = 1
    var changeable = 1
    var quickSearch = 1
    var categories: [String] = []
    var header: [String: String] = [:]
    var style: Style?

    var id: String { key }

    init(key: String = "", name: String = "", api: String = "", ext: String = "", type: Int = 0) {
        (self.key, self.name, self.api, self.ext, self.type) = (key, name, api, ext, type)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        key = c.str(AnyKey("key"))
        name = c.str(AnyKey("name"))
        api = c.str(AnyKey("api"))
        ext = c.str(AnyKey("ext"))
        jar = c.str(AnyKey("jar"))
        playUrl = c.str(AnyKey("playUrl"))
        type = c.int(AnyKey("type")) ?? 0
        hide = c.int(AnyKey("hide")) ?? 0
        timeout = max(c.int(AnyKey("timeout")) ?? 15, 1)
        searchable = c.int(AnyKey("searchable")) ?? 1
        changeable = c.int(AnyKey("changeable")) ?? 1
        quickSearch = c.int(AnyKey("quickSearch")) ?? 1
        categories = c.list(AnyKey("categories"))
        header = c.dict(AnyKey("header"))
        style = try? c.decodeIfPresent(Style.self, forKey: AnyKey("style"))
    }

    /// iOS 上能跑的站点：CMS(0/1/2)、自定义(4)、JS 爬虫(3 + .js)、已内置 JS 版的 jar 爬虫
    var isSupported: Bool {
        switch type {
        case 0, 1, 2, 4: true
        // ponytail: 填了仓库就把所有 csp_ 当可用，仓库里没有的在首次调用时报错
        case 3: api.contains(".js") || !Self.spiderCandidates(api).isEmpty
        default: false
        }
    }

    /// jar 爬虫类名 → 包内 JS 版（Resources/js/spider/）。别名指向同一实现。
    static let bundledSpiders: [String: String] = [
        "Douban": "Douban", "DoubanLocal": "Douban",
        "Jianpian": "Jianpian",
        "Dm84": "Dm84",
        "Ysj": "Ysj",
        "Zxzj": "Zxzj",
        "FirstAid": "FirstAid",
        "Kanqiu": "Kanqiu",
        "AppYsV2": "AppYsV2",
        "AList": "AList",
        "WebDAV": "WebDAV",
        "XPath": "XPath",
        "XPathFilter": "XPathFilter",
        "XPathMac": "XPathMac",
        "XPathMacFilter": "XPathMacFilter",
        "Quark": "Quark",
        "UC": "UC",
        "TianYi": "TianYi",
        "Pan123": "Pan123",
        "Ali": "Ali",
        "YiDongYun": "YiDongYun",
        "TgSearchQuark": "TgSearchQuark",
        "TgSearch123": "TgSearch123",
        "TgSearch139": "TgSearch139",
        "TgSearch189": "TgSearch189",
        "TgSearchBaidu": "TgSearchBaidu",
        "DianYingYunJi": "DianYingYunJi",
        "KuaKeS": "KuaKeS",
        "Xb6v": "Xb6v",
        "Emby": "Emby",
    ]

    /// `csp_Xxx` → `assets://js/spider/Xxx.js`，没有内置版本返回 nil
    static func bundledSpider(_ api: String) -> String? {
        guard api.hasPrefix("csp_"), let name = bundledSpiders[String(api.dropFirst(4))] else { return nil }
        return "assets://js/spider/\(name).js"
    }

    /// 外接 JS 爬虫仓库（目录地址）。设置后 csp_Xxx 先找 `<仓库>/Xxx.js`
    nonisolated(unsafe) static var spiderRepo: String {
        get { UserDefaults.standard.string(forKey: "spider.repo") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "spider.repo") }
    }

    /// csp_Xxx 的候选 JS 地址：仓库优先，其次内置
    static func spiderCandidates(_ api: String, repo: String = spiderRepo) -> [String] {
        guard api.hasPrefix("csp_"), api.count > 4 else { return [] }
        var out: [String] = []
        if !repo.isEmpty {
            out.append(repo.hasSuffix("/") ? repo + api.dropFirst(4) + ".js" : repo + "/" + api.dropFirst(4) + ".js")
        }
        if let b = bundledSpider(api) { out.append(b) }
        return out
    }
}
