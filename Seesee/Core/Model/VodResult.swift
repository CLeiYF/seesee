import Foundation

/// 对应 bean/Result.java，字段名与 CMS / 爬虫 JSON 一致
struct VodResult: Decodable {
    var classes: [VodClass] = []
    var list: [Vod] = []
    var filters: [String: [Filter]] = [:]
    var url = PlayURL()
    var parse: Int?
    var jx = 0
    var playUrl = ""
    var header: [String: String] = [:]
    var flag = ""
    var pagecount: Int?
    var msg = ""
    var code: Int?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        classes = c.list(AnyKey("class"))
        list = c.list(AnyKey("list"))
        filters = Self.filters(c)
        url = (try? c.decodeIfPresent(PlayURL.self, forKey: AnyKey("url"))) ?? PlayURL()
        parse = c.int(AnyKey("parse"))
        jx = c.int(AnyKey("jx")) ?? 0
        playUrl = c.str(AnyKey("playUrl"))
        header = Self.header(c)
        flag = c.str(AnyKey("flag"))
        pagecount = c.int(AnyKey("pagecount"))
        msg = c.str(AnyKey("msg"))
        code = c.int(AnyKey("code"))
    }

    static func json(_ text: String) -> VodResult {
        (try? JSONDecoder().decode(VodResult.self, from: Data(text.utf8))) ?? VodResult()
    }

    static func from(type: Int, _ text: String) -> VodResult {
        type == 0 ? XMLResult.parse(text) : json(text)
    }

    /// 值可以是对象或数组（对应 FilterAdapter）
    private static func filters(_ c: KeyedDecodingContainer<AnyKey>) -> [String: [Filter]] {
        guard let n = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("filters")) else { return [:] }
        var map: [String: [Filter]] = [:]
        for k in n.allKeys {
            if let one = try? n.decode(Filter.self, forKey: k) { map[k.stringValue] = [one] }
            else { map[k.stringValue] = n.list(k) }
        }
        return map
    }

    /// header 可以是对象，也可以是 JSON 字符串
    private static func header(_ c: KeyedDecodingContainer<AnyKey>) -> [String: String] {
        let d = c.dict(AnyKey("header"))
        if !d.isEmpty { return d }
        let s = c.str(AnyKey("header"))
        guard let data = s.data(using: .utf8), let obj = try? JSONDecoder().decode(AnyJSON.self, from: data) else { return [:] }
        return obj.dict
    }
}

struct VodClass: Decodable, Hashable, Identifiable {
    var typeId = ""
    var typeName = ""
    var typeFlag = ""
    var style: Style?

    var id: String { typeId }

    init(typeId: String, typeName: String) { (self.typeId, self.typeName) = (typeId, typeName) }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        typeId = c.str(AnyKey("type_id"))
        if typeId.isEmpty { typeId = c.str(AnyKey("id")) }
        typeName = c.str(AnyKey("type_name"))
        if typeName.isEmpty { typeName = c.str(AnyKey("name")) }
        typeFlag = c.str(AnyKey("type_flag"))
        style = Style.from(land: c.int(AnyKey("land")) ?? 0, circle: c.int(AnyKey("circle")) ?? 0, ratio: c.double(AnyKey("ratio")) ?? 0)
    }
}

struct Filter: Decodable, Hashable {
    struct Value: Decodable, Hashable {
        var n = ""
        var v = ""
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            n = c.str(AnyKey("n"))
            v = c.str(AnyKey("v"))
        }
    }

    var key = ""
    var name = ""
    var initial: String?
    var value: [Value] = []

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        key = c.str(AnyKey("key"))
        name = c.str(AnyKey("name"))
        initial = c.contains(AnyKey("init")) ? c.str(AnyKey("init")) : nil
        value = c.list(AnyKey("value"))
    }
}

struct Episode: Hashable, Identifiable {
    var name: String
    var url: String
    var id: String { name + "\u{1}" + url }
}

struct Flag: Hashable, Identifiable {
    var flag: String
    var episodes: [Episode] = []
    var id: String { flag }

    /// 对应 Flag.createEpisode：`#` 分集，`$` 分名称与地址，无名称时用两位序号
    init(flag: String, urls: String) {
        self.flag = flag
        let items = urls.split(separator: "#", omittingEmptySubsequences: false)
        for (i, item) in items.enumerated() {
            let number = String(format: "%02d", i + 1)
            let parts = item.split(separator: "$", maxSplits: 1, omittingEmptySubsequences: false)
            let ep = parts.count > 1
                ? Episode(name: parts[0].isEmpty ? number : parts[0].trimmingCharacters(in: .whitespaces), url: String(parts[1]))
                : Episode(name: number, url: String(item))
            if !episodes.contains(ep) { episodes.append(ep) }
        }
    }
}

struct Vod: Decodable, Hashable, Identifiable {
    var vodId = ""
    var vodName = ""
    var typeName = ""
    var vodPic = ""
    var vodRemarks = ""
    var vodYear = ""
    var vodArea = ""
    var vodDirector = ""
    var vodActor = ""
    var vodContent = ""
    var vodPlayFrom = ""
    var vodPlayUrl = ""
    var vodTag = ""
    var style: Style?
    /// XML 源直接给出线路
    var xmlFlags: [Flag] = []
    /// 搜索结果所属站点
    var siteKey = ""

    var id: String { siteKey + "\u{1}" + vodId }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        vodId = c.str(AnyKey("vod_id"))
        vodName = c.str(AnyKey("vod_name"))
        typeName = c.str(AnyKey("type_name"))
        vodPic = c.str(AnyKey("vod_pic")).trimmingCharacters(in: .whitespaces)
        vodRemarks = c.str(AnyKey("vod_remarks"))
        vodYear = c.str(AnyKey("vod_year"))
        vodArea = c.str(AnyKey("vod_area"))
        vodDirector = c.str(AnyKey("vod_director"))
        vodActor = c.str(AnyKey("vod_actor"))
        vodContent = c.str(AnyKey("vod_content"))
        vodPlayFrom = c.str(AnyKey("vod_play_from"))
        vodPlayUrl = c.str(AnyKey("vod_play_url"))
        vodTag = c.str(AnyKey("vod_tag"))
        style = (try? c.decodeIfPresent(Style.self, forKey: AnyKey("style")))
            ?? Style.from(land: c.int(AnyKey("land")) ?? 0, circle: c.int(AnyKey("circle")) ?? 0, ratio: c.double(AnyKey("ratio")) ?? 0)
    }

    var isFolder: Bool { vodTag == "folder" }

    /// 对应 Vod.setVodFlags：`$$$` 分线路
    var flags: [Flag] {
        if !xmlFlags.isEmpty { return xmlFlags }
        let froms = vodPlayFrom.components(separatedBy: "$$$")
        let urls = vodPlayUrl.components(separatedBy: "$$$")
        return froms.enumerated().compactMap { i, from in
            guard !from.isEmpty, i < urls.count else { return nil }
            return Flag(flag: from.trimmingCharacters(in: .whitespaces), urls: urls[i])
        }
    }
}

/// 对应 Url + UrlAdapter：字符串 / [n,v,n,v] / {values:[{n,v}],position}
struct PlayURL: Decodable {
    var values: [(n: String, v: String)] = []
    var position = 0

    init(_ v: String = "") { if !v.isEmpty { values = [("", v)] } }

    init(from decoder: Decoder) throws {
        self.init()
        if let c = try? decoder.singleValueContainer(), let s = try? c.decode(String.self) {
            if !s.isEmpty { values = [("", s)] }
        } else if var a = try? decoder.unkeyedContainer() {
            var flat: [String] = []
            while !a.isAtEnd, let item = try? a.decode(AnyJSON.self) { flat.append(item.string) }
            values = stride(from: 0, to: flat.count - 1, by: 2).map { (flat[$0], flat[$0 + 1]) }
        } else {
            let c = try decoder.container(keyedBy: AnyKey.self)
            let items: [Filter.Value] = c.list(AnyKey("values"))
            values = items.map { ($0.n, $0.v) }
            position = min(c.int(AnyKey("position")) ?? 0, max(values.count - 1, 0))
        }
    }

    var v: String { position < values.count ? values[position].v : "" }
    var isEmpty: Bool { v.isEmpty }
}
