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
        case 3: api.contains(".js") || Self.bundledSpider(api) != nil
        default: false
        }
    }

    /// jar 爬虫类名 → 包内 JS 版（Resources/js/spider/）。别名指向同一实现。
    static let bundledSpiders: [String: String] = [
        "Douban": "Douban", "DoubanLocal": "Douban",
    ]

    /// `csp_Xxx` → `assets://js/spider/Xxx.js`，没有内置版本返回 nil
    static func bundledSpider(_ api: String) -> String? {
        guard api.hasPrefix("csp_"), let name = bundledSpiders[String(api.dropFirst(4))] else { return nil }
        return "assets://js/spider/\(name).js"
    }
}
