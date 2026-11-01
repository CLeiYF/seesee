import XCTest
@testable import Seesee

final class LiveTests: XCTestCase {
    private let utc8 = TimeZone(secondsFromGMT: 8 * 3600)!

    func testM3U() {
        let m3u = """
        #EXTM3U x-tvg-url="http://epg/e.xml" catchup="append" catchup-source="?playseek=${(b)yyyyMMddHHmmss}-${(e)yyyyMMddHHmmss}"
        #EXTINF:-1 tvg-id="cctv1" tvg-name="CCTV1" tvg-logo="http://logo/1.png" group-title="央视",CCTV-1 综合
        #EXTVLCOPT:http-user-agent=UA1
        http://a/1.m3u8|Referer=http://r
        #EXTINF:-1 tvg-id="cctv1" group-title="央视",CCTV-1 综合
        http://b/1.m3u8
        #EXTINF:-1 group-title="加密_1234",秘密台
        http://c/2.m3u8
        """
        var live = Live(name: "L")
        let groups = LiveParser.parse(m3u, live: live)
        XCTAssertEqual(groups.map(\.name), ["央视", "加密"])
        XCTAssertEqual(groups[1].pass, "1234")
        let c = groups[0].channels[0]
        XCTAssertEqual(c.name, "CCTV-1 综合")
        XCTAssertEqual(c.urls, ["http://a/1.m3u8", "http://b/1.m3u8"])
        XCTAssertEqual(c.tvgId, "cctv1")
        XCTAssertEqual(c.logo, "http://logo/1.png")
        XCTAssertEqual(c.number, "001")
        XCTAssertEqual(c.headers["User-Agent"], "UA1")
        XCTAssertEqual(c.headers["Referer"], "http://r")
        XCTAssertEqual(c.catchup?.type, "append")
        XCTAssertEqual(LiveParser.m3uEPG(m3u), "http://epg/e.xml")
        // live.pass=true 时分组名不拆密码
        live.pass = true
        XCTAssertEqual(LiveParser.parse(m3u, live: live).last?.name, "加密_1234")
    }

    func testTXTWithLinesAndGenres() {
        let txt = """
        央视,#genre#
        ua=TXTUA
        CCTV1,http://a/1.m3u8#http://b/1.m3u8$备用
        CCTV2,http://a/2.m3u8
        卫视_888,#genre#
        湖南,http://h/1.m3u8
        """
        var live = Live(name: "L")
        live.epg = "http://epg/?ch={name}&date={date}"
        live.logo = "http://logo/{name}.png"
        let groups = LiveParser.parse(txt, live: live)
        XCTAssertEqual(groups.map(\.name), ["央视", "卫视"])
        XCTAssertEqual(groups[1].pass, "888")
        let c = groups[0].channels[0]
        XCTAssertEqual(c.urls.count, 2)
        XCTAssertEqual(Channel.line(c.urls[1]).name, "备用")
        XCTAssertEqual(Channel.line(c.urls[1]).url, "http://b/1.m3u8")
        XCTAssertEqual(c.ua, "TXTUA")
        // #genre# 会清空上一组的 ua=（与原项目一致）
        XCTAssertEqual(groups[1].channels[0].ua, "")
        XCTAssertEqual(c.epg, "http://epg/?ch=CCTV1&date={date}")
        XCTAssertEqual(c.logo, "http://logo/CCTV1.png")
        XCTAssertEqual(groups[1].channels[0].number, "003")
    }

    func testJSONGroups() {
        let json = #"[{"name":"G_9","channel":[{"name":"A","urls":["http://a"],"number":"7"}]}]"#
        let g = LiveParser.parse(json, live: Live(name: "L"))
        XCTAssertEqual(g.first?.name, "G")
        XCTAssertEqual(g.first?.pass, "9")
        XCTAssertEqual(g.first?.channels.first?.number, "7")
    }

    func testCatchupAppendAndDefault() {
        let start = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 08:00 +0800
        let end = start.addingTimeInterval(3600)
        let append = Catchup(type: "append", source: "?playseek=${(b)yyyyMMddHHmmss}-${(e)yyyyMMddHHmmss}", replace: "/PLTV/,/TVOD/")
        XCTAssertEqual(append.url("http://h/PLTV/1/index.m3u8", start: start, end: end, timeZone: utc8),
                       "http://h/TVOD/1/index.m3u8?playseek=20240101080000-20240101090000")
        XCTAssertEqual(append.url("http://h/live.m3u8?a=1", start: start, end: end, timeZone: utc8),
                       "http://h/live.m3u8?a=1&playseek=20240101080000-20240101090000")
        let def = Catchup(type: "default", source: "http://h/back?s={utc:YmdHMS}&e={utcend:YmdHMS}")
        XCTAssertEqual(def.url("http://ignored", start: start, end: end), "http://h/back?s=1704067200&e=1704070800")
    }

    func testEPGJson() {
        let json = #"{"date":"2024-01-01","epg_data":[{"title":"新闻","start":"08:00","end":"09:00"},{"title":"夜间","start":"23:30","end":"00:30"},{"title":"新闻","start":"08:00","end":"09:00"}]}"#
        let list = EPG.parse(json, timeZone: utc8)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].start, Date(timeIntervalSince1970: 1_704_067_200))
        XCTAssertEqual(list[1].end.timeIntervalSince(list[1].start), 3600) // 跨零点
        XCTAssertEqual(EPG.url("http://e/?d={date}", date: list[0].start, timeZone: utc8), "http://e/?d=2024-01-01")
    }

    func testXMLTVByIdAndDisplayName() {
        let xml = """
        <?xml version="1.0"?><tv>
        <channel id="1"><display-name>CCTV1</display-name><display-name>CCTV-1 综合</display-name></channel>
        <programme start="20240101080000 +0800" stop="20240101090000 +0800" channel="1"><title>朝闻天下</title></programme>
        <programme start="20240101070000 +0800" stop="20240101080000 +0800" channel="1"><title>早间</title></programme>
        </tv>
        """
        let map = XMLTV.parse(Data(xml.utf8), timeZone: utc8)
        XCTAssertEqual(map["1"]?.map(\.title), ["早间", "朝闻天下"])
        XCTAssertEqual(map["CCTV-1 综合"]?.count, 2)
        XCTAssertEqual(map["1"]?.last?.start, Date(timeIntervalSince1970: 1_704_067_200))
    }

    func testGunzip() {
        // printf 'hello gzip' | gzip -c
        let gz = Data(base64Encoded: "H4sIADyH5moAA8tIzcnJV0ivyiwAABlq0t8KAAAA")!
        XCTAssertEqual(gz.gunzipped.map { String(decoding: $0, as: UTF8.self) }, "hello gzip")
        XCTAssertNil(Data("plain".utf8).gunzipped)
    }

    func testConfigLives() throws {
        let c = try VodConfig.parse(#"{"lives":[{"name":"L","url":"./l.txt","epg":"http://e/?ch={name}&date={date},http://x/e.xml.gz","pass":true,"boot":1}]}"#)
        XCTAssertEqual(c.lives.first?.name, "L")
        XCTAssertEqual(c.lives.first?.epgApi, "http://e/?ch={name}&date={date}")
        XCTAssertEqual(c.lives.first?.epgXml, ["http://x/e.xml.gz"])
        XCTAssertEqual(c.lives.first?.pass, true)
        XCTAssertEqual(c.lives.first?.boot, true)
    }
}
