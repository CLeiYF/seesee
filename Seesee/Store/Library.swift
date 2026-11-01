import Foundation
import Observation

struct ConfigItem: Codable, Hashable, Identifiable {
    var url: String
    var text = ""
    var home = ""
    var time = Date()
    var id: String { url }
}

struct HistoryItem: Codable, Hashable, Identifiable {
    var config: String
    var siteKey: String
    var vodId: String
    var vodName = ""
    var vodPic = ""
    var flag = ""
    var episode = ""
    var position: Double = 0
    var duration: Double = 0
    var skip = PlaybackSkip()
    var time = Date()
    var id: String { Library.key(config, siteKey, vodId) }

    init(config: String, siteKey: String, vodId: String, vodName: String = "", vodPic: String = "", flag: String = "",
         episode: String = "", position: Double = 0, duration: Double = 0, skip: PlaybackSkip = PlaybackSkip(), time: Date = Date()) {
        (self.config, self.siteKey, self.vodId, self.vodName, self.vodPic) = (config, siteKey, vodId, vodName, vodPic)
        (self.flag, self.episode, self.position, self.duration, self.skip, self.time) = (flag, episode, position, duration, skip, time)
    }

    /// 旧数据没有 skip 字段
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        config = try c.decode(String.self, forKey: .config)
        siteKey = try c.decode(String.self, forKey: .siteKey)
        vodId = try c.decode(String.self, forKey: .vodId)
        vodName = try c.decodeIfPresent(String.self, forKey: .vodName) ?? ""
        vodPic = try c.decodeIfPresent(String.self, forKey: .vodPic) ?? ""
        flag = try c.decodeIfPresent(String.self, forKey: .flag) ?? ""
        episode = try c.decodeIfPresent(String.self, forKey: .episode) ?? ""
        position = try c.decodeIfPresent(Double.self, forKey: .position) ?? 0
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        skip = try c.decodeIfPresent(PlaybackSkip.self, forKey: .skip) ?? PlaybackSkip()
        time = try c.decodeIfPresent(Date.self, forKey: .time) ?? Date()
    }
}

struct KeepItem: Codable, Hashable, Identifiable {
    var config: String
    var siteKey: String
    var vodId: String
    var vodName = ""
    var vodPic = ""
    var time = Date()
    var id: String { Library.key(config, siteKey, vodId) }
}

/// 本地数据：配置历史、观看记录、收藏、搜索词、站点搜索开关；备份即整个文件。
/// ponytail: 单个 JSON 文件，每次修改全量写入；记录上万条再换数据库
@MainActor
@Observable
final class Library {
    struct Snapshot: Codable, Equatable {
        var configs: [ConfigItem] = []
        var history: [HistoryItem] = []
        var keep: [KeepItem] = []
        var words: [String] = []
        var unsearchable: Set<String> = []

        init() {}

        /// 缺字段的旧备份也能导入
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            configs = try c.decodeIfPresent([ConfigItem].self, forKey: .configs) ?? []
            history = try c.decodeIfPresent([HistoryItem].self, forKey: .history) ?? []
            keep = try c.decodeIfPresent([KeepItem].self, forKey: .keep) ?? []
            words = try c.decodeIfPresent([String].self, forKey: .words) ?? []
            unsearchable = try c.decodeIfPresent(Set<String>.self, forKey: .unsearchable) ?? []
        }
    }

    static let historyLimit = 300
    static let wordLimit = 20
    nonisolated static let defaultFile = URL.applicationSupportDirectory.appending(path: "library.json")

    private(set) var data = Snapshot()
    @ObservationIgnored private let file: URL?

    /// file 为 nil 时只在内存里（测试用）
    init(file: URL? = Library.defaultFile) {
        self.file = file
        if let file, let d = try? Data(contentsOf: file), let s = try? Self.decoder.decode(Snapshot.self, from: d) { data = s }
    }

    nonisolated static func key(_ parts: String...) -> String { parts.joined(separator: "\u{1}") }

    // MARK: 配置

    func config(_ url: String) -> ConfigItem? { data.configs.first { $0.url == url } }

    func saveConfig(url: String, text: String, time: Date = .now) {
        mutate {
            var item = $0.configs.first { $0.url == url } ?? ConfigItem(url: url)
            item.text = text
            item.time = time
            $0.configs.removeAll { $0.url == url }
            $0.configs.insert(item, at: 0)
        }
    }

    func setHome(url: String, key: String) {
        mutate { if let i = $0.configs.firstIndex(where: { $0.url == url }) { $0.configs[i].home = key } }
    }

    func removeConfig(_ url: String) { mutate { $0.configs.removeAll { $0.url == url } } }

    // MARK: 观看记录（按配置隔离，对应原项目 cid）

    func history(config: String) -> [HistoryItem] { data.history.filter { $0.config == config } }

    func history(config: String, siteKey: String, vodId: String) -> HistoryItem? {
        let id = Self.key(config, siteKey, vodId)
        return data.history.first { $0.id == id }
    }

    func record(_ item: HistoryItem) {
        mutate {
            $0.history.removeAll { $0.id == item.id }
            $0.history.insert(item, at: 0)
            $0.history = Array($0.history.prefix(Self.historyLimit))
        }
    }

    func removeHistory(_ id: String) { mutate { $0.history.removeAll { $0.id == id } } }

    func clearHistory(config: String) { mutate { $0.history.removeAll { $0.config == config } } }

    // MARK: 收藏

    func keep(config: String) -> [KeepItem] { data.keep.filter { $0.config == config } }

    func isKept(_ id: String) -> Bool { data.keep.contains { $0.id == id } }

    func toggleKeep(_ item: KeepItem) {
        mutate {
            if $0.keep.contains(where: { $0.id == item.id }) { $0.keep.removeAll { $0.id == item.id } }
            else { $0.keep.insert(item, at: 0) }
        }
    }

    // MARK: 搜索

    func addWord(_ word: String) {
        mutate {
            $0.words.removeAll { $0 == word }
            $0.words.insert(word, at: 0)
            $0.words = Array($0.words.prefix(Self.wordLimit))
        }
    }

    func clearWords() { mutate { $0.words = [] } }

    func isSearchable(_ site: Site) -> Bool { site.searchable == 1 && !data.unsearchable.contains(site.key) }

    func setSearchable(_ key: String, _ on: Bool) {
        mutate { if on { $0.unsearchable.remove(key) } else { $0.unsearchable.insert(key) } }
    }

    // MARK: 备份

    func export() throws -> Data { try Self.encoder.encode(data) }

    func restore(_ backup: Data) throws {
        let s = try Self.decoder.decode(Snapshot.self, from: backup)
        mutate { $0 = s }
    }

    private func mutate(_ change: (inout Snapshot) -> Void) {
        change(&data)
        guard let file else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Self.encoder.encode(data).write(to: file, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()
}
