import CommonCrypto
import CryptoKit
import Foundation
import Security

/// 对应 quickjs/utils/Crypto.java：md5X / aesX / rsaX 的行为（失败返回空串）
enum JSCrypto {
    static func md5(_ text: String) -> String {
        Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// mode 形如 "AES/CBC/PKCS5" / "AES/ECB/PKCS5" / "AES/CBC/No"；key、iv 不足 16 字节补 0
    static func aes(mode: String, encrypt: Bool, input: String, inBase64: Bool, key: String, iv: String?, outBase64: Bool) -> String {
        let upper = mode.uppercased()
        let ecb = upper.contains("ECB")
        let padding = !upper.contains("NOPADDING") && !upper.hasSuffix("/NO")
        let keyData = pad16(Data(key.utf8))
        let ivData = ecb ? nil : pad16(Data((iv ?? "").utf8))
        guard let inData = inBase64 ? base64(input) : Data(input.utf8),
              let out = crypt(encrypt, inData, key: keyData, iv: ivData, padding: padding) else { return "" }
        return outBase64 ? out.base64EncodedString() : HTTP.string(out)
    }

    /// RSA/ECB/PKCS1，按模长分块；pub 为 true 用公钥（X.509 PEM），否则私钥（PKCS#8 PEM）
    static func rsa(pub: Bool, encrypt: Bool, input: String, inBase64: Bool, key: String, outBase64: Bool) -> String {
        guard let secKey = rsaKey(key, pub: pub),
              let inData = inBase64 ? base64(input) : Data(input.utf8) else { return "" }
        let size = SecKeyGetBlockSize(secKey)
        let block = encrypt ? size - 11 : size
        var out = Data()
        var i = 0
        while i < inData.count {
            let chunk = inData.subdata(in: i..<min(i + block, inData.count))
            guard let r = rsaBlock(secKey, chunk, encrypt: encrypt, pub: pub) else { return "" }
            out.append(r)
            i += block
        }
        return outBase64 ? out.base64EncodedString() : HTTP.string(out)
    }

    // MARK: -

    static func base64(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "_", with: "/").replacingOccurrences(of: "-", with: "+").filter { !$0.isWhitespace }
        t += String(repeating: "=", count: (4 - t.count % 4) % 4)
        return Data(base64Encoded: t)
    }

    private static func pad16(_ d: Data) -> Data {
        d.count >= 16 ? d : d + Data(count: 16 - d.count)
    }

    private static func crypt(_ encrypt: Bool, _ input: Data, key: Data, iv: Data?, padding: Bool) -> Data? {
        guard [16, 24, 32].contains(key.count) else { return nil }
        var options = CCOptions(padding ? kCCOptionPKCS7Padding : 0)
        if iv == nil { options |= CCOptions(kCCOptionECBMode) }
        var out = Data(count: input.count + kCCBlockSizeAES128)
        let cap = out.count
        var moved = 0
        let status = out.withUnsafeMutableBytes { o in
            input.withUnsafeBytes { i in
                key.withUnsafeBytes { k in
                    (iv ?? Data(count: 16)).withUnsafeBytes { v in
                        CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), options,
                                k.baseAddress, key.count, iv == nil ? nil : v.baseAddress,
                                i.baseAddress, input.count, o.baseAddress, cap, &moved)
                    }
                }
            }
        }
        return status == kCCSuccess ? out.prefix(moved) : nil
    }

    /// PEM → SecKey。Security 只认 PKCS#1，所以剥掉 X.509 / PKCS#8 外层
    private static func rsaKey(_ pem: String, pub: Bool) -> SecKey? {
        let body = pem.components(separatedBy: .newlines).filter { !$0.hasPrefix("-----") }.joined()
        guard let der = base64(body) else { return nil }
        let pkcs1 = stripHeader(der) ?? der
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: pub ? kSecAttrKeyClassPublic : kSecAttrKeyClassPrivate,
        ]
        return SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, nil)
    }

    private static func rsaBlock(_ key: SecKey, _ data: Data, encrypt: Bool, pub: Bool) -> Data? {
        // 私钥"加密" = PKCS1 签名原文；公钥"解密" = 用公钥还原（对应 Java 的 Cipher 用法）
        if encrypt && pub { return SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, data as CFData, nil) as Data? }
        if !encrypt && !pub { return SecKeyCreateDecryptedData(key, .rsaEncryptionPKCS1, data as CFData, nil) as Data? }
        if encrypt { return SecKeyCreateSignature(key, .rsaSignatureDigestPKCS1v15Raw, data as CFData, nil) as Data? }
        return rawPublicDecrypt(key, data)
    }

    /// 公钥解密私钥签名：raw RSA 后去掉 PKCS1 type-1 填充（00 01 FF.. 00 msg）
    private static func rawPublicDecrypt(_ key: SecKey, _ data: Data) -> Data? {
        guard let raw = SecKeyCreateEncryptedData(key, .rsaEncryptionRaw, data as CFData, nil) as Data?,
              raw.count > 11, raw[raw.startIndex] == 0, raw[raw.startIndex + 1] == 1,
              let sep = raw.dropFirst(2).firstIndex(of: 0) else { return nil }
        return raw[(sep + 1)...]
    }

    /// 解析 DER：SEQUENCE{ [INTEGER version,] SEQUENCE algId, BIT STRING|OCTET STRING key }，取出内层 key
    private static func stripHeader(_ der: Data) -> Data? {
        let b = [UInt8](der)
        var i = 0
        func length() -> Int? {
            guard i < b.count else { return nil }
            let first = Int(b[i]); i += 1
            guard first & 0x80 != 0 else { return first }
            let n = first & 0x7f
            guard n <= 4, i + n <= b.count else { return nil }
            var len = 0
            for _ in 0..<n { len = len << 8 | Int(b[i]); i += 1 }
            return len
        }
        guard b.first == 0x30 else { return nil }
        i = 1
        guard length() != nil else { return nil }
        if i < b.count, b[i] == 0x02 { i += 1; guard let l = length() else { return nil }; i += l } // version
        guard i < b.count, b[i] == 0x30 else { return nil } // 已经是 PKCS#1
        i += 1
        guard let algLen = length() else { return nil }
        i += algLen
        guard i < b.count, b[i] == 0x03 || b[i] == 0x04 else { return nil }
        let bitString = b[i] == 0x03
        i += 1
        guard let keyLen = length(), i + keyLen <= b.count else { return nil }
        if bitString { i += 1 } // 未使用位数
        return Data(b[i..<(i + keyLen - (bitString ? 1 : 0))])
    }
}
