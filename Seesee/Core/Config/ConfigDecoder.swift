import CommonCrypto
import Foundation

/// 对应 ../TV/app/.../api/Decoder.java
enum ConfigDecoder {
    enum Failure: Error { case empty, aes }

    static func verify(url: String, data: String) throws -> String {
        guard !data.isEmpty else { throw Failure.empty }
        if isObject(data) { return fix(url: url, data: data) }
        var data = data
        if data.contains("**") { data = base64(data) }
        if data.hasPrefix("2423") { data = try cbc(data) }
        return fix(url: url, data: data)
    }

    static func fix(url: String, data: String) -> String {
        var data = data
        let jsURI = #/"(\.|\.\.)/(.?|.+?)\.js\?(.?|.+?)"/#
        for m in data.matches(of: jsURI).map({ String($0.output.0) }) {
            var t = m.replacingOccurrences(of: "\"./", with: "\"" + resolve(url, "./"))
            t = t.replacingOccurrences(of: "\"../", with: "\"" + resolve(url, "../"))
            t = t.replacingOccurrences(of: "./", with: "__JS1__").replacingOccurrences(of: "../", with: "__JS2__")
            data = data.replacingOccurrences(of: m, with: t)
        }
        if data.contains("../") { data = data.replacingOccurrences(of: "../", with: resolve(url, "../")) }
        if data.contains("./") { data = data.replacingOccurrences(of: "./", with: resolve(url, "./")) }
        return data.replacingOccurrences(of: "__JS1__", with: "./").replacingOccurrences(of: "__JS2__", with: "../")
    }

    static func resolve(_ base: String, _ ref: String) -> String {
        URL(string: ref, relativeTo: URL(string: base))?.absoluteString ?? ref
    }

    private static func isObject(_ s: String) -> Bool {
        guard let d = s.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: d)) is [String: Any]
    }

    private static func base64(_ data: String) -> String {
        guard let m = data.firstMatch(of: #/[A-Za-z0-9]{8}\*\*/#) else { return data }
        let payload = data[m.range.upperBound...].filter { !$0.isWhitespace }
        let padded = payload + String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let d = Data(base64Encoded: padded) else { return data }
        return HTTP.string(d)
    }

    private static func cbc(_ data: String) throws -> String {
        guard let raw = hex(data) else { throw Failure.aes }
        let decode = HTTP.string(raw).lowercased()
        guard let s = decode.range(of: "$#"), let e = decode.range(of: "#$"), s.upperBound <= e.lowerBound else { throw Failure.aes }
        let key = padEnd(String(decode[s.upperBound..<e.lowerBound]))
        let iv = padEnd(String(decode.suffix(13)))
        guard let start = data.range(of: "2324"), data.count >= 26 else { throw Failure.aes }
        let end = data.index(data.endIndex, offsetBy: -26)
        guard start.upperBound <= end, let cipher = hex(String(data[start.upperBound..<end])) else { throw Failure.aes }
        return HTTP.string(try decrypt(cipher, key: Data(key.utf8), iv: Data(iv.utf8)))
    }

    static func decrypt(_ cipher: Data, key: Data, iv: Data) throws -> Data {
        var out = Data(count: cipher.count + kCCBlockSizeAES128)
        let outCount = out.count
        var moved = 0
        let status = out.withUnsafeMutableBytes { o in
            cipher.withUnsafeBytes { c in
                key.withUnsafeBytes { k in
                    iv.withUnsafeBytes { v in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                k.baseAddress, key.count, v.baseAddress, c.baseAddress, cipher.count,
                                o.baseAddress, outCount, &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw Failure.aes }
        return out.prefix(moved)
    }

    static func hex(_ s: String) -> Data? {
        guard s.count % 2 == 0 else { return nil }
        var data = Data(capacity: s.count / 2)
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
            data.append(b)
            i = j
        }
        return data
    }

    private static func padEnd(_ key: String) -> String {
        key.count >= 16 ? String(key.prefix(16)) : key + String(repeating: "0", count: 16 - key.count)
    }
}
