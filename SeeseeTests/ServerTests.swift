import XCTest
@testable import Seesee

final class ServerTests: XCTestCase {
    func testParseRequestWithQueryAndForm() {
        let raw = "POST /proxy?do=js&siteKey=a%20b HTTP/1.1\r\nHost: x\r\nContent-Type: application/x-www-form-urlencoded\r\nContent-Length: 7\r\n\r\nk=v&z=1"
        let r = LocalServer.parse(Data(raw.utf8))
        XCTAssertEqual(r?.path, "/proxy")
        XCTAssertEqual(r?.query["siteKey"], "a b")
        XCTAssertEqual(r?.query["k"], "v")
        XCTAssertEqual(r?.headers["host"], "x")
        // body 未读完时继续等待
        XCTAssertNil(LocalServer.parse(Data(raw.dropLast(3).utf8)))
    }

    func testConvertProxyScheme() {
        let s = LocalServer.shared
        s.start()
        XCTAssertEqual(s.convert("proxy://do=js&url=x"), "http://127.0.0.1:\(s.port)/proxy?do=js&url=x")
        XCTAssertEqual(s.convert("http://a"), "http://a")
    }

    func testCacheRouteSharesLocalStore() throws {
        JSRuntime.store = UserDefaults(suiteName: "srv-\(UUID().uuidString)")!
        ServerRoutes.install()
        let port = LocalServer.shared.start()
        XCTAssertGreaterThanOrEqual(port, 9978)
        let base = "http://127.0.0.1:\(port)/cache"
        _ = try blocking { try await URLSession.shared.data(from: URL(string: "\(base)?do=set&rule=r&key=k&value=v1")!) }
        XCTAssertEqual(JSRuntime.store.string(forKey: "cache_r_k"), "v1")
        let (d, _) = try blocking { try await URLSession.shared.data(from: URL(string: "\(base)?do=get&rule=r&key=k")!) }
        XCTAssertEqual(String(decoding: d, as: UTF8.self), "v1")
    }

    func testJSSpiderProxyThroughServer() async throws {
        let rt = JSRuntime(siteKey: "px") { _ in """
        export default {
          init() {},
          home() { return JSON.stringify({ class: [{ type_id: '1', type_name: getProxy(true) }] }) },
          proxy(params) { return [200, 'text/plain', 'hello ' + params.what, { 'X-Test': '1' }] },
        }
        """ }
        let spider = JSSpider(site: Site(key: "px", api: "http://h/px.js", type: 3), runtime: rt)
        JSSpider.register(spider)
        defer { JSSpider.reset() }
        ServerRoutes.install()
        LocalServer.shared.start()
        let proxy = try await spider.home().classes.first?.typeName ?? ""
        XCTAssertTrue(proxy.hasPrefix("http://127.0.0.1:"), proxy)
        XCTAssertTrue(proxy.contains("siteKey=px"))
        let (data, res) = try await URLSession.shared.data(from: URL(string: proxy + "&what=world")!)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "hello world")
        XCTAssertEqual((res as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Test"), "1")
    }
}
