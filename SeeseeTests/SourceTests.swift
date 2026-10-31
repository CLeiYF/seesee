import XCTest
@testable import Seesee

final class SourceTests: XCTestCase {
    func testJSONCategoryParams() throws {
        let m = MockFetch()
        let api = makeAPI(Site(key: "a", api: "http://x/api.php/provide/vod/", type: 1), fetch: m.fetch)
        _ = try blocking { try await api.category(tid: "1", page: 2, filter: true, extend: ["area": "美国"]) }
        XCTAssertEqual(m.params["ac"], "detail")
        XCTAssertEqual(m.params["t"], "1")
        XCTAssertEqual(m.params["pg"], "2")
        XCTAssertEqual(m.params["f"], #"{"area":"美国"}"#)
        XCTAssertEqual(m.last?.httpMethod, "GET")
    }

    func testXMLCategoryUsesVideolist() throws {
        let m = MockFetch()
        let api = makeAPI(Site(key: "a", api: "http://x/xml", type: 0), fetch: m.fetch)
        _ = try blocking { try await api.category(tid: "1", page: 1, filter: false, extend: ["a": "b"]) }
        XCTAssertEqual(m.params["ac"], "videolist")
        XCTAssertNil(m.params["f"])
    }

    func testExtendAndPost() throws {
        let m = MockFetch()
        let api = makeAPI(Site(key: "a", api: "http://x", ext: String(repeating: "e", count: 1001), type: 1), fetch: m.fetch)
        _ = try blocking { try await api.detail(ids: ["1", "2"]) }
        XCTAssertEqual(m.last?.httpMethod, "POST")
        XCTAssertEqual(m.params["ids"], "1,2")
        XCTAssertEqual(m.params["extend"]?.count, 1001)
    }

    func testSearchTraditionalToSimplifiedAndSiteKey() throws {
        let m = MockFetch()
        m.on("wd=", #"{"list":[{"vod_id":"1","vod_name":"A","vod_pic":"p"}]}"#)
        let api = makeAPI(Site(key: "s1", api: "http://x", type: 1), fetch: m.fetch)
        let r = try blocking { try await api.search("電影", quick: false, page: 1) }
        XCTAssertEqual(m.params["wd"], "电影")
        XCTAssertEqual(r.list.first?.siteKey, "s1")
    }

    func testHomeFetchesPicsWhenMissing() throws {
        let m = MockFetch()
        m.on("http://x", #"{"class":[{"type_id":1,"type_name":"电影"}],"list":[{"vod_id":"7","vod_name":"A"}]}"#)
        m.on("ids=7", #"{"list":[{"vod_id":"7","vod_name":"A","vod_pic":"http://p"}]}"#)
        let api = makeAPI(Site(key: "a", api: "http://x", type: 1), fetch: m.fetch)
        let r = try blocking { try await api.home() }
        XCTAssertEqual(r.classes.count, 1)
        XCTAssertEqual(r.list.first?.vodPic, "http://p")
    }

    func testCMSPlayerParseFlag() throws {
        let api = makeAPI(Site(key: "a", api: "http://x", type: 1), fetch: MockFetch().fetch)
        let direct = try blocking { try await api.player(flag: "m3u8", id: "https://cdn.example.com/v/index.m3u8", vipFlags: []) }
        XCTAssertEqual(direct.parse, 0)
        let page = try blocking { try await api.player(flag: "qq", id: "https://v.qq.com/x/cover/abc.html", vipFlags: []) }
        XCTAssertEqual(page.parse, 1)
    }

    func testCustomTypeParams() throws {
        let m = MockFetch()
        m.on("ext.json", "EXT")
        m.on("play=", #"{"parse":0,"url":"http://v.m3u8"}"#)
        let api = makeAPI(Site(key: "c", api: "http://x/api", ext: "http://x/ext.json", type: 4), fetch: m.fetch)
        _ = try blocking { try await api.home() }
        XCTAssertEqual(m.params["filter"], "true")
        XCTAssertEqual(m.params["extend"], "EXT")
        _ = try blocking { try await api.category(tid: "1", page: 1, filter: true, extend: ["a": "?"]) }
        XCTAssertEqual(m.params["ext"], "eyJhIjoiPyJ9")
        let r = try blocking { try await api.player(flag: "f", id: "p1", vipFlags: []) }
        XCTAssertEqual(m.params["play"], "p1")
        XCTAssertEqual(r.flag, "f")
        XCTAssertEqual(r.url.v, "http://v.m3u8")
        XCTAssertEqual(m.requests.filter { $0.url?.absoluteString.contains("ext.json") == true }.count, 1)
    }

    func testUnsupportedThrows() {
        let api = makeAPI(Site(key: "j", api: "csp_Foo", type: 3))
        XCTAssertThrowsError(try blocking { try await api.home() })
    }

    func testSniffer() {
        XCTAssertTrue(Sniffer.isVideoFormat("https://cdn.example.com/a/index.m3u8?t=1"))
        XCTAssertTrue(Sniffer.isVideoFormat("rtmp://live.example.com/x"))
        XCTAssertFalse(Sniffer.isVideoFormat("https://www.example.com/play/1.html"))
        XCTAssertFalse(Sniffer.isVideoFormat("https://jx.example.com/?url=http://a.m3u8"))
    }

    func testConfigLoaderFollowsDepot() throws {
        let m = MockFetch()
        m.on("depot.json", #"{"urls":[{"name":"一","url":"http://h/one/c.json"}]}"#)
        m.on("one/c.json", #"{"sites":[{"key":"k","name":"K","type":1,"api":"./api"}]}"#)
        let r = try blocking { try await ConfigLoader.load("http://h/depot.json", fetch: m.fetch) }
        XCTAssertEqual(r.url, "http://h/one/c.json")
        XCTAssertEqual(r.depots.count, 1)
        XCTAssertEqual(r.config.sites.first?.api, "http://h/one/api")
    }

    func testHostHeaders() throws {
        HTTP.hostHeaders = [HostHeader(host: "cmvideo.cn", header: ["User-Agent": "okhttp/3.12.13"])]
        defer { HTTP.hostHeaders = [] }
        XCTAssertEqual(try HTTP.get("http://gslb.cmvideo.cn/x").value(forHTTPHeaderField: "User-Agent"), "okhttp/3.12.13")
        XCTAssertEqual(try HTTP.get("http://other.com/x").value(forHTTPHeaderField: "User-Agent"), HTTP.chrome)
    }
}
