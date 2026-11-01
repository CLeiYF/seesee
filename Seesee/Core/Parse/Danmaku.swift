import Foundation

/// 结果里的 danmaku 来源（对应 bean/Danmaku + DanmakuAdapter）：字符串地址、JSON 数组字符串或对象数组
struct DanmakuSource: Decodable, Hashable {
    var name = ""
    var url = ""

    init(url: String, name: String = "") { (self.url, self.name) = (url, name.isEmpty ? url : name) }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        url = c.str(AnyKey("url"))
        name = c.str(AnyKey("name"))
        if name.isEmpty { name = url }
    }

    /// danmaku 字段：字符串（地址或 JSON 数组文本）或数组
    static func list(_ c: KeyedDecodingContainer<AnyKey>, _ key: AnyKey) -> [DanmakuSource] {
        let arr: [DanmakuSource] = c.list(key)
        if !arr.isEmpty { return arr }
        let s = c.str(key).trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("["), let d = s.data(using: .utf8), let v = try? JSONDecoder().decode([Lossy<DanmakuSource>].self, from: d) {
            return v.compactMap(\.value)
        }
        return s.isEmpty ? [] : [DanmakuSource(url: s)]
    }
}

/// 一条弹幕（对应 bean/DanmakuData）
struct DanmakuItem: Hashable {
    enum Kind: Int { case scroll = 1, bottom = 4, top = 5 }
    var time: Double
    var kind: Kind
    var size: Double
    /// 0xRRGGBB
    var color: UInt32
    var text: String
}

/// 弹幕解析（对应 player/danmaku/Parser）：
/// - XML（B 站格式）：`<d p="时间,类型,字号,颜色,…">文本</d>`
/// - TXT：`[时间,类型,字号,颜色]文本`
enum DanmakuParser {
    static func parse(_ text: String) -> [DanmakuItem] {
        let xml = text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<")
        var out: [DanmakuItem] = []
        if xml {
            for m in text.matches(of: #/p="([^"]+)"[^>]*>([^<]+)</#) {
                if let d = item(String(m.output.1), String(m.output.2)) { out.append(d) }
            }
        } else {
            for line in text.split(whereSeparator: \.isNewline) {
                guard let m = line.firstMatch(of: #/\[(.*?)\](.*)/#) else { continue }
                if let d = item(String(m.output.1), String(m.output.2)) { out.append(d) }
            }
        }
        return out.sorted { $0.time < $1.time }
    }

    private static func item(_ param: String, _ raw: String) -> DanmakuItem? {
        let p = param.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard p.count >= 4, let time = Double(p[0]), let type = Int(p[1]), let size = Double(p[2]), let color = UInt64(p[3]) else { return nil }
        // 7 为高级弹幕，跳过；2/3 视为滚动（与原项目一致）
        guard type != 7 else { return nil }
        let kind: DanmakuItem.Kind = type == 4 ? .bottom : type == 5 ? .top : .scroll
        let text = raw.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&lt;", with: "<")
        guard !text.isEmpty else { return nil }
        return DanmakuItem(time: time, kind: kind, size: size, color: UInt32(truncatingIfNeeded: color) & 0xFFFFFF, text: text)
    }

    /// [from, to) 时间段内的弹幕（items 已按时间排序）
    static func window(_ items: [DanmakuItem], from: Double, to: Double) -> ArraySlice<DanmakuItem> {
        var lo = 0, hi = items.count
        while lo < hi { let mid = (lo + hi) / 2; if items[mid].time < from { lo = mid + 1 } else { hi = mid } }
        var end = lo
        while end < items.count, items[end].time < to { end += 1 }
        return items[lo..<end]
    }
}
