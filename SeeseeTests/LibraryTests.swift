import XCTest
@testable import Seesee

@MainActor
final class LibraryTests: XCTestCase {
    func testHistoryDedupesAndScopesByConfig() {
        let lib = Library(file: nil)
        lib.record(HistoryItem(config: "c1", siteKey: "s", vodId: "1", episode: "01"))
        lib.record(HistoryItem(config: "c1", siteKey: "s", vodId: "2"))
        lib.record(HistoryItem(config: "c1", siteKey: "s", vodId: "1", episode: "02", position: 30))
        lib.record(HistoryItem(config: "c2", siteKey: "s", vodId: "1"))
        let h = lib.history(config: "c1")
        XCTAssertEqual(h.map(\.vodId), ["1", "2"])
        XCTAssertEqual(h.first?.episode, "02")
        XCTAssertEqual(lib.history(config: "c1", siteKey: "s", vodId: "1")?.position, 30)
        lib.clearHistory(config: "c1")
        XCTAssertTrue(lib.history(config: "c1").isEmpty)
        XCTAssertEqual(lib.history(config: "c2").count, 1)
    }

    func testHistoryLimit() {
        let lib = Library(file: nil)
        for i in 0..<(Library.historyLimit + 5) { lib.record(HistoryItem(config: "c", siteKey: "s", vodId: "\(i)")) }
        XCTAssertEqual(lib.data.history.count, Library.historyLimit)
        XCTAssertEqual(lib.data.history.first?.vodId, "\(Library.historyLimit + 4)")
    }

    func testKeepToggle() {
        let lib = Library(file: nil)
        let k = KeepItem(config: "c", siteKey: "s", vodId: "1")
        lib.toggleKeep(k)
        XCTAssertTrue(lib.isKept(k.id))
        lib.toggleKeep(k)
        XCTAssertFalse(lib.isKept(k.id))
    }

    func testWordsMostRecentFirst() {
        let lib = Library(file: nil)
        ["a", "b", "a"].forEach(lib.addWord)
        XCTAssertEqual(lib.data.words, ["a", "b"])
    }

    func testSearchableRespectsConfigAndUser() {
        let lib = Library(file: nil)
        var off = Site(key: "x")
        off.searchable = 0
        XCTAssertFalse(lib.isSearchable(off))
        let on = Site(key: "y")
        XCTAssertTrue(lib.isSearchable(on))
        lib.setSearchable("y", false)
        XCTAssertFalse(lib.isSearchable(on))
    }

    func testPersistAndBackupRoundTrip() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "lib-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let lib = Library(file: file)
        lib.saveConfig(url: "http://c", text: "{}", time: Date(timeIntervalSince1970: 1_700_000_000.5))
        // 毫秒精度的时间才能精确往返
        lib.toggleKeep(KeepItem(config: "http://c", siteKey: "s", vodId: "1", vodName: "A", time: Date(timeIntervalSince1970: 1_700_000_000.123)))
        XCTAssertEqual(Library(file: file).data, lib.data)

        let backup = try lib.export()
        let other = Library(file: nil)
        try other.restore(backup)
        XCTAssertEqual(other.data, lib.data)
        XCTAssertThrowsError(try other.restore(Data("nope".utf8)))
        // 只有部分字段的备份也能导入
        try other.restore(Data(#"{"words":["x"]}"#.utf8))
        XCTAssertEqual(other.data.words, ["x"])
        XCTAssertTrue(other.data.keep.isEmpty)
    }

    func testSearchRunnerFansOutAndSkipsFailures() async {
        let sites = [Site(key: "a", type: 1), Site(key: "b", type: 1), Site(key: "jar", api: "csp_X", type: 3), Site(key: "c", type: 1)]
        let stream = SearchRunner.run("k", sites: sites, quick: false, limit: 2) { site in
            Fake(key: site.key)
        }
        var keys: [String] = []
        for await hit in stream {
            keys.append(hit.site.key)
            XCTAssertEqual(hit.result.list.first?.siteKey, hit.site.key)
        }
        XCTAssertEqual(Set(keys), ["a", "c"])
    }

    private struct Fake: SiteAPI {
        let key: String
        func search(_ key: String, quick: Bool, page: Int) async throws -> VodResult {
            if self.key == "b" { throw URLError(.timedOut) }
            return VodResult.json(#"{"list":[{"vod_id":"1","vod_name":"A"}]}"#)
        }
        func home() async throws -> VodResult { VodResult() }
        func category(tid: String, page: Int, filter: Bool, extend: [String: String]) async throws -> VodResult { VodResult() }
        func detail(ids: [String]) async throws -> VodResult { VodResult() }
        func player(flag: String, id: String, vipFlags: [String]) async throws -> VodResult { VodResult() }
    }
}
