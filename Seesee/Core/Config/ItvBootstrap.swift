import Foundation

/// 对应 spider1202.jar 的 UpdateManager + ConfigManager：
/// itv/tv/ctv 地址只是入口，真正的站点在更新包 TVBox.zip 里。
/// 下载更新包，版本变了就解压到本地，然后改用本地的 local_java.json（固定用 _java 版，见 csp_Emby）。
enum ItvBootstrap {
    /// 更新源，顺序同 UpdateManager.a
    static let domains = [
        "https://gitee.com/mang_zhe_xue_xi/letmeseesee/raw/backup",
        "http://ctv.mangzhexuexi.com",
        "https://itv.mangzhexuexi.com",
        "https://tv.mangzhexuexi.com",
    ]

    /// 解压目录：<Application Support>/itv，内含 config/（包内 TVBoxOSC/tvbox）与 TVBox/（cookie 等）。
    /// 不能叫 tvbox：大小写不敏感的文件系统上与 TVBox 冲突（模拟器上写入报 EIO）
    static var root: URL { URL.applicationSupportDirectory.appending(path: "itv", directoryHint: .isDirectory) }
    static var configFile: URL { root.appending(path: "config/local_java.json") }
    private static var versionFile: URL { root.appending(path: "TVBox/local_version.txt") }

    /// 是否是需要走更新包的入口地址
    static func matches(_ url: String) -> Bool {
        guard let host = URL(string: url)?.host?.lowercased() else { return false }
        return ["itv.mangzhexuexi.com", "tv.mangzhexuexi.com", "ctv.mangzhexuexi.com"].contains(host)
    }

    /// 确保本地配置可用，返回 (本地配置 file:// 地址, 配置文本)。
    /// 按顺序试各更新源；都失败但本地已有旧版时用旧版，否则抛错。
    static func prepare(fetch: HTTP.Fetch) async throws -> (url: String, text: String) {
        var lastError: Error = URLError(.cannotLoadFromNetwork)
        for domain in domains {
            do {
                let zip = try await fetch(try HTTP.get(domain + "/TVBox.zip", timeout: 30))
                try install(zip)
                break
            } catch {
                lastError = error
            }
        }
        guard let text = try? String(contentsOf: configFile, encoding: .utf8) else { throw lastError }
        return (configFile.absoluteString, text)
    }

    /// 读包内版本号，与本地不同（或本地缺配置）才重新解压
    static func install(_ zip: Data) throws {
        let entries = try ZipReader.entries(zip)
        guard let v = entries.first(where: { $0.name == "TVBox/local_version.txt" }),
              entries.contains(where: { $0.name == "TVBoxOSC/tvbox/local_java.json" }) else {
            throw ZipReader.Failure.corrupt
        }
        let remote = String(decoding: try ZipReader.data(zip, v), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let local = (try? String(contentsOf: versionFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        if remote == local, FileManager.default.fileExists(atPath: configFile.path) { return }
        // 先解压到临时目录再整体替换，避免中途失败留下半套文件
        let tmp = root.deletingLastPathComponent().appending(path: "itv.tmp", directoryHint: .isDirectory)
        let fm = FileManager.default
        try? fm.removeItem(at: tmp)
        _ = try ZipReader.extract(zip, to: tmp.appending(path: "config"), prefix: "TVBoxOSC/tvbox/")
        _ = try ZipReader.extract(zip, to: tmp.appending(path: "TVBox"), prefix: "TVBox/")
        try? fm.removeItem(at: root)
        try fm.moveItem(at: tmp, to: root)
    }

    /// 本地服务 /file/<相对路径> 的取文件（对应 jar 的 127.0.0.1:9978/file/TVBox/...）
    static func file(_ path: String) -> Data? {
        let rel = path.split(separator: "/").filter { !$0.isEmpty && $0 != ".." }.joined(separator: "/")
        guard !rel.isEmpty else { return nil }
        return try? Data(contentsOf: root.appending(path: rel))
    }
}
