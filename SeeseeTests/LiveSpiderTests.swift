import XCTest
@testable import Seesee

/// 联网测试：在真实 JavaScriptCore 里跑内置网盘爬虫（Node 冒烟脚本用 curl 模拟 req，这里验证 App 运行时）。
/// 默认跳过；运行：TEST_RUNNER_SEESEE_LIVE=1 xcodebuild test … -only-testing:SeeseeTests/LiveSpiderTests
final class LiveSpiderTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SEESEE_LIVE"] == "1", "联网测试，设 SEESEE_LIVE=1 开启")
    }

    private func spider(_ name: String, ext: String = "") -> JSSpider {
        let rt = JSRuntime(siteKey: name) { url in
            guard let p = JSRuntime.bundledPath(url) else { throw URLError(.fileDoesNotExist) }
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            return try String(contentsOf: root.appending(path: "Seesee/Resources/js/\(p)"), encoding: .utf8)
        }
        return JSSpider(site: Site(key: name, api: "assets://js/spider/\(name).js", ext: ext, type: 3), runtime: rt)
    }

    /// 公开分享匿名列集；缺 cookie 的线路给出 ext 提示
    func testQuarkListsPublicShare() async throws {
        let s = spider("Quark")
        let d = try await s.detail(ids: ["https://pan.quark.cn/s/7afba66418d6"])
        let v = try XCTUnwrap(d.list.first)
        XCTAssertFalse(v.vodPlayUrl.isEmpty)
        let ep = try XCTUnwrap(v.vodPlayUrl.components(separatedBy: "$$$")[0].components(separatedBy: "#")[0].components(separatedBy: "$").last)
        let p = try await s.player(flag: v.vodPlayFrom.components(separatedBy: "$$$")[0], id: ep, vipFlags: [])
        XCTAssertTrue(p.url.v.isEmpty && p.msg.contains("ext.cookie"), p.msg)
    }

    /// 移动云盘「极速」线路匿名可播
    func testYidongFastLinePlaysAnonymously() async throws {
        let s = spider("YiDongYun")
        let d = try await s.detail(ids: ["https://yun.139.com/shareweb/#/w/i/2qidZRh2H2m6p"])
        let v = try XCTUnwrap(d.list.first)
        let froms = v.vodPlayFrom.components(separatedBy: "$$$"), urls = v.vodPlayUrl.components(separatedBy: "$$$")
        let i = try XCTUnwrap(froms.firstIndex { $0.contains("极速") }, v.vodPlayFrom)
        let ep = try XCTUnwrap(urls[i].components(separatedBy: "#")[0].components(separatedBy: "$").last)
        let p = try await s.player(flag: froms[i], id: ep, vipFlags: [])
        XCTAssertTrue(p.url.v.hasPrefix("http"), p.msg)
    }

    /// 盘搜：搜索返回网盘链接
    func testTgSearchQuarkSearches() async throws {
        let r = try await spider("TgSearchQuark").search("流浪地球", quick: false, page: 1)
        XCTAssertFalse(r.list.isEmpty)
    }
}
