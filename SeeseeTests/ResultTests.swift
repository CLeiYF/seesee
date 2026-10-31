import XCTest
@testable import Seesee

final class ResultTests: XCTestCase {
    func testSiteLossyFields() throws {
        let json = #"{"sites":[{"key":"a","name":"A","type":"1","api":"http://x","timeout":"0","searchable":0,"ext":{"k":1},"header":{"User-Agent":"u"}},{"key":"a","name":"dup"},{"name":"nokey"}],"spider":"./s.jar"}"#
        let c = try VodConfig.parse(json)
        XCTAssertEqual(c.sites.count, 1)
        let s = c.sites[0]
        XCTAssertEqual(s.type, 1)
        XCTAssertEqual(s.timeout, 1)
        XCTAssertEqual(s.searchable, 0)
        XCTAssertEqual(s.ext, #"{"k":1}"#)
        XCTAssertEqual(s.header["User-Agent"], "u")
        XCTAssertEqual(s.jar, "./s.jar")
    }

    func testSupportedTypes() {
        XCTAssertTrue(Site(api: "http://x", type: 1).isSupported)
        XCTAssertTrue(Site(api: "./a.js", type: 3).isSupported)
        XCTAssertFalse(Site(api: "csp_Foo", type: 3).isSupported)
        XCTAssertFalse(Site(api: "./a.py", type: 3).isSupported)
    }

    func testURLVariants() {
        XCTAssertEqual(VodResult.json(#"{"url":"http://a.m3u8"}"#).url.v, "http://a.m3u8")
        XCTAssertEqual(VodResult.json(#"{"url":["HD","http://hd","SD","http://sd"]}"#).url.values.count, 2)
        let obj = VodResult.json(#"{"url":{"values":[{"n":"a","v":"1"},{"n":"b","v":"2"}],"position":1}}"#)
        XCTAssertEqual(obj.url.v, "2")
    }

    func testFiltersObjectOrArray() {
        let r = VodResult.json(#"{"filters":{"1":[{"key":"area","name":"地区","value":[{"n":"全部","v":""}]}],"2":{"key":"year","name":"年份","init":"2024","value":[]}}}"#)
        XCTAssertEqual(r.filters["1"]?.first?.key, "area")
        XCTAssertEqual(r.filters["2"]?.first?.initial, "2024")
    }

    func testHeaderAsString() {
        XCTAssertEqual(VodResult.json(#"{"header":"{\"Referer\":\"r\"}"}"#).header["Referer"], "r")
    }

    func testPlayFlagsSplit() {
        let r = VodResult.json(#"{"list":[{"vod_id":1,"vod_name":"A","vod_play_from":"f1$$$f2","vod_play_url":"第1集$u1#第2集$u2$$$u3"}]}"#)
        let flags = r.list[0].flags
        XCTAssertEqual(r.list[0].vodId, "1")
        XCTAssertEqual(flags.map(\.flag), ["f1", "f2"])
        XCTAssertEqual(flags[0].episodes.map(\.name), ["第1集", "第2集"])
        XCTAssertEqual(flags[1].episodes[0].name, "01")
        XCTAssertEqual(flags[1].episodes[0].url, "u3")
    }

    func testXML() {
        let xml = #"<?xml version="1.0" encoding="utf-8"?><rss><class><ty id="1">电影</ty><ty id="2">剧集</ty></class><list page="1" pagecount="3"><video><id>9</id><name><![CDATA[A]]></name><pic>p</pic><note>HD</note><dl><dd flag="m3u8"><![CDATA[E1$u1#E2$u2]]></dd></dl></video></list></rss>"#
        let r = VodResult.from(type: 0, xml)
        XCTAssertEqual(r.classes.map(\.typeName), ["电影", "剧集"])
        XCTAssertEqual(r.classes[0].typeId, "1")
        XCTAssertEqual(r.pagecount, 3)
        XCTAssertEqual(r.list.count, 1)
        XCTAssertEqual(r.list[0].vodName, "A")
        XCTAssertEqual(r.list[0].vodRemarks, "HD")
        XCTAssertEqual(r.list[0].flags.first?.flag, "m3u8")
        XCTAssertEqual(r.list[0].flags.first?.episodes.count, 2)
    }
}
