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
        // 配置请求用 OkHttp UA（有的服务器对浏览器 UA 302 到网页）
        XCTAssertEqual(m.last?.value(forHTTPHeaderField: "User-Agent"), "okhttp/3.15")
    }

    func testHostHeaders() throws {
        HTTP.hostHeaders = [HostHeader(host: "cmvideo.cn", header: ["User-Agent": "okhttp/3.12.13"])]
        defer { HTTP.hostHeaders = [] }
        XCTAssertEqual(try HTTP.get("http://gslb.cmvideo.cn/x").value(forHTTPHeaderField: "User-Agent"), "okhttp/3.12.13")
        XCTAssertEqual(try HTTP.get("http://other.com/x").value(forHTTPHeaderField: "User-Agent"), HTTP.okhttp)
    }

    /// 默认 UA 与安卓 OkHttp 一致（配置服务器按 UA 分流），仅 gitcode.net 用 Chrome；调用方 header 优先
    func testDefaultUserAgent() throws {
        XCTAssertTrue(HTTP.okhttp.hasPrefix("okhttp/"))
        XCTAssertEqual(try HTTP.get("https://itv.mangzhexuexi.com/").value(forHTTPHeaderField: "User-Agent"), HTTP.okhttp)
        XCTAssertEqual(try HTTP.get("https://gitcode.net/a/b.json").value(forHTTPHeaderField: "User-Agent"), HTTP.chrome)
        XCTAssertEqual(try HTTP.get("https://a.com", headers: ["User-Agent": "X"]).value(forHTTPHeaderField: "User-Agent"), "X")
    }

    func testNetRulesHostsAndProxy() throws {
        defer { NetRules.configure(proxy: [], hosts: []) }
        let c = try VodConfig.parse(#"{"hosts":["cache.ott.*.itv.cmvideo.cn=base.cdn.cn","a.com=b.com"],"proxy":[{"name":"p","hosts":["google"],"urls":["http://127.0.0.1:7890"]}]}"#)
        XCTAssertEqual(c.hosts.count, 2)
        NetRules.configure(proxy: c.proxy, hosts: c.hosts)
        // 包含匹配：与 OkDns 一致，整个域名替换为新域名，原 Host 保留在头里
        let r = NetRules.rewrite(try HTTP.get("http://x.a.com/p?q=1"))
        XCTAssertEqual(r.url?.absoluteString, "http://b.com/p?q=1")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Host"), "x.a.com")
        // 正则整串匹配
        XCTAssertEqual(NetRules.rewrite(try HTTP.get("http://cache.ott.bestlive.itv.cmvideo.cn/x")).url?.host, "base.cdn.cn")
        XCTAssertEqual(NetRules.rewrite(try HTTP.get("http://other.org/x")).url?.host, "other.org")
        // 代理只作用于命中的域名
        XCTAssertFalse(NetRules.session(for: URL(string: "https://www.google.com")) === URLSession.shared)
        XCTAssertTrue(NetRules.session(for: URL(string: "https://baidu.com")) === URLSession.shared)
        XCTAssertTrue(NetRules.session(for: URL(string: "http://127.0.0.1:9978/proxy")) === URLSession.shared)
    }
}
