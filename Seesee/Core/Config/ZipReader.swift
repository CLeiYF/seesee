import Foundation

/// 最小 zip 读取：解析中央目录，支持 stored(0) 与 deflate(8)。
/// ponytail: 不支持 zip64、加密、跨卷；itv 更新包（几百 KB、普通 zip）足够
enum ZipReader {
    struct Entry {
        let name: String
        let method: UInt16
        let compressed: Int
        let size: Int
        let offset: Int
    }

    enum Failure: Error { case notZip, unsupported(UInt16), corrupt }

    private static func u16(_ d: Data, _ i: Int) -> Int {
        Int(d[d.startIndex + i]) | Int(d[d.startIndex + i + 1]) << 8
    }

    private static func u32(_ d: Data, _ i: Int) -> Int {
        u16(d, i) | u16(d, i + 2) << 16
    }

    /// 列出所有条目（读中央目录）
    static func entries(_ d: Data) throws -> [Entry] {
        // 从尾部找 End of Central Directory（PK\5\6）
        guard d.count >= 22 else { throw Failure.notZip }
        var eocd = -1
        var i = d.count - 22
        while i >= max(0, d.count - 65_557) {
            if u32(d, i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw Failure.notZip }
        let count = u16(d, eocd + 10)
        var p = u32(d, eocd + 16)
        var out: [Entry] = []
        for _ in 0..<count {
            guard p + 46 <= d.count, u32(d, p) == 0x02014b50 else { throw Failure.corrupt }
            let nameLen = u16(d, p + 28), extraLen = u16(d, p + 30), commentLen = u16(d, p + 32)
            guard p + 46 + nameLen <= d.count else { throw Failure.corrupt }
            let raw = d.subdata(in: (d.startIndex + p + 46)..<(d.startIndex + p + 46 + nameLen))
            // 文件名：UTF-8 标志位(0x800) 或本身就是合法 UTF-8；否则按 GBK（Windows 中文压缩包）
            let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
            let name = String(data: raw, encoding: .utf8) ?? String(data: raw, encoding: gbk) ?? ""
            out.append(Entry(name: name, method: UInt16(u16(d, p + 10)), compressed: u32(d, p + 20),
                             size: u32(d, p + 24), offset: u32(d, p + 42)))
            p += 46 + nameLen + extraLen + commentLen
        }
        return out
    }

    /// 取出一个条目的内容
    static func data(_ d: Data, _ e: Entry) throws -> Data {
        // 本地文件头的文件名/扩展字段长度可能与中央目录不同，按本地头重新算数据起点
        guard e.offset + 30 <= d.count, u32(d, e.offset) == 0x04034b50 else { throw Failure.corrupt }
        let start = e.offset + 30 + u16(d, e.offset + 26) + u16(d, e.offset + 28)
        guard start + e.compressed <= d.count else { throw Failure.corrupt }
        let body = d.subdata(in: (d.startIndex + start)..<(d.startIndex + start + e.compressed))
        switch e.method {
        case 0: return body
        // NSData 的 .zlib 即 raw deflate（RFC 1951），正是 zip 用的格式
        case 8: return try (body as NSData).decompressed(using: .zlib) as Data
        default: throw Failure.unsupported(e.method)
        }
    }

    /// 解压到目录；只保留 prefix 开头的条目，并去掉该前缀。拒绝 `..` 路径穿越
    static func extract(_ d: Data, to dir: URL, prefix: String = "") throws -> Int {
        let fm = FileManager.default
        var n = 0
        for e in try entries(d) where e.name.hasPrefix(prefix) && !e.name.hasSuffix("/") {
            let rel = String(e.name.dropFirst(prefix.count))
            guard !rel.isEmpty, !rel.split(separator: "/").contains("..") else { continue }
            let dest = dir.appending(path: rel)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data(d, e).write(to: dest, options: .atomic)
            n += 1
        }
        return n
    }
}
