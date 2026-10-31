import Foundation

/// 配置/接口里数字、字符串、对象常常混用，统一宽松解码
struct AnyJSON: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = NSNull() }
        else if let v = try? c.decode(Bool.self) { value = v }
        else if let v = try? c.decode(Int.self) { value = v }
        else if let v = try? c.decode(Double.self) { value = v }
        else if let v = try? c.decode(String.self) { value = v }
        else if let v = try? c.decode([AnyJSON].self) { value = v.map(\.value) }
        else { value = try c.decode([String: AnyJSON].self).mapValues(\.value) }
    }

    /// 字符串原样返回，其余序列化为 JSON 文本（对应 ExtAdapter）
    var string: String {
        if let s = value as? String { return s }
        if value is NSNull { return "" }
        if JSONSerialization.isValidJSONObject(value), let d = try? JSONSerialization.data(withJSONObject: value) { return HTTP.string(d) }
        return "\(value)"
    }

    var int: Int? {
        switch value {
        case let v as Int: v
        case let v as Double: Int(v)
        case let v as Bool: v ? 1 : 0
        case let v as String: Int(v.trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }

    var double: Double? {
        switch value {
        case let v as Double: v
        case let v as Int: Double(v)
        case let v as String: Double(v)
        default: nil
        }
    }

    var dict: [String: String] {
        (value as? [String: Any])?.mapValues { AnyJSON(raw: $0).string } ?? [:]
    }

    init(raw: Any) { value = raw }
}

extension KeyedDecodingContainer {
    func str(_ key: Key) -> String { (try? decodeIfPresent(AnyJSON.self, forKey: key))??.string ?? "" }
    func int(_ key: Key) -> Int? { (try? decodeIfPresent(AnyJSON.self, forKey: key))??.int }
    func double(_ key: Key) -> Double? { (try? decodeIfPresent(AnyJSON.self, forKey: key))??.double }
    func dict(_ key: Key) -> [String: String] { (try? decodeIfPresent(AnyJSON.self, forKey: key))??.dict ?? [:] }
    /// 数组里单个坏元素不影响其它元素
    func list<T: Decodable>(_ key: Key) -> [T] {
        ((try? decodeIfPresent([Lossy<T>].self, forKey: key)) ?? nil)?.compactMap(\.value) ?? []
    }
}

struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// 允许任意字符串作为 CodingKey
struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
