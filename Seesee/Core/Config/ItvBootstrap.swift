import Foundation
import UIKit

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
        seedPanCreds()
        return (configFile.absoluteString, text)
    }

    /// 更新包 TVBox/ 下的网盘凭证 → JS 网盘库的 local('pan', key)（pan/common.js cred()）。
    /// 包内值变了才覆盖，避免把 uc.js 刷新后写回的 refresh_token 换成旧的。
    static func seedPanCreds(store: UserDefaults = JSRuntime.store, read: (String) -> Data? = file) {
        // 文件 → (JSON 字段, 网盘库凭证键)
        let map = [("quark_cookie.txt", "cookie", "quark_cookie"), ("uc_cookie.txt", "cookie", "uc_cookie"),
                   ("uc_token.txt", "refresh_token", "uc_token_cookie"), ("baidu.txt", "cookie", "baidu_cookie")]
        for (name, field, key) in map {
            guard let data = read("TVBox/" + name),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let value = (obj[field] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { continue }
            let seeded = "itv.seeded." + key
            guard store.string(forKey: seeded) != value else { continue }
            store.set(value, forKey: "cache_pan_" + key)
            store.set(value, forKey: seeded)
        }
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

    // MARK: 设备与心跳（对应 DeviceInfoHelper / HeartbeatManager）

    /// 本机设备 id/名，存在 cache_device_id / cache_device_name（Emby.js 用 local.get('', 'device_id') 读同一份）
    static var device: (id: String, name: String) {
        let d = UserDefaults.standard
        if let id = d.string(forKey: "cache_device_id"), !id.isEmpty { return (id, d.string(forKey: "cache_device_name") ?? "") }
        // jar 用 Android ID；iOS 用 identifierForVendor 去掉连字符
        let id = (UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        var u = utsname()
        uname(&u)
        let name = withUnsafeBytes(of: u.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        d.set(id, forKey: "cache_device_id")
        d.set(name, forKey: "cache_device_name")
        return (id, name)
    }

    nonisolated(unsafe) private static var beating: Task<Void, Never>?

    /// 加载 itv 配置后开始心跳：每 60 秒 POST /api/heartbeat，首次延后 60 秒（同 Init.run(c, 60000)）
    @MainActor static func startHeartbeat(fetch: @escaping HTTP.Fetch) {
        guard beating == nil else { return }
        _ = device  // Emby.js 播放前要读到本机 id
        beating = Task.detached {
            var extraAt = Date.distantPast
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                // extra 首次及每 10 分钟带一次
                let withExtra = Date().timeIntervalSince(extraAt) >= 600
                if withExtra { extraAt = Date() }
                guard let req = try? await heartbeatRequest(extra: withExtra) else { continue }
                _ = try? await fetch(req)
            }
        }
    }

    @MainActor static func heartbeatRequest(extra: Bool) throws -> URLRequest {
        let (id, name) = device
        var extraText = ""
        if extra {
            // ponytail: jar 的 extra 还带宿主 App 的搜索关键词和播放历史；这里只发 preferences，两个列表留空，需要时再接 Library
            let prefs: [String: Any] = ["current_version": UserDefaults.standard.string(forKey: "cache_current_version") ?? "", "device_id": id, "device_name": name]
            let e: [String: Any] = ["preferences": prefs, "search_keywords": [Any](), "history": [Any]()]
            extraText = String(decoding: try JSONSerialization.data(withJSONObject: e), as: UTF8.self)
        }
        let body: [String: Any] = [
            "device_id": id, "brand": "Apple", "manufacturer": "Apple", "model": name, "device_name": name,
            "android_version": UIDevice.current.systemVersion, "android_sdk": "", "architecture": "arm64",
            "platform": UIDevice.current.userInterfaceIdiom == .tv ? "tv" : "phone",
            "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "extra": extraText,
        ]
        var r = URLRequest(url: URL(string: "https://itv.mangzhexuexi.com/api/heartbeat")!, timeoutInterval: 15)
        r.httpMethod = "POST"
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        r.setValue("okhttp", forHTTPHeaderField: "User-Agent")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("*/*", forHTTPHeaderField: "Accept")
        return r
    }
}
