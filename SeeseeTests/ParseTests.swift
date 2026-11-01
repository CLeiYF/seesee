import XCTest
@testable import Seesee

final class ParseTests: XCTestCase {
    private let long = "https://cdn.example.com/hls/abcdefghijklmnopqrstuvwxyz/index.m3u8"

    func testJSONParseReadsUrlOrDataUrlAndHeaders() throws {
        let m = MockFetch()
        m.on("jx.a", #"{"url":"\#(long)","User-Agent":"UA","referer":"R"}"#)
        m.on("jx.b", #"{"data":{"url":"\#(long)"}}"#)
        let a = try blocking { try await ParseJob.json(Parse(type: 1, url: "http://jx.a/?url=", name: "A"), url: "https://v.qq.com/x.html", fetch: m.fetch) }
        XCTAssertEqual(a.url, long)
        XCTAssertEqual(a.headers, ["User-Agent": "UA", "Referer": "R"])
        XCTAssertEqual(a.from, "A")
        XCTAssertEqual(m.last?.url?.absoluteString, "http://jx.a/?url=https://v.qq.com/x.html")
        var b = Parse(type: 1, url: "http://jx.b/?url=")
        b.header = ["Referer": "fallback"]
        let r = try blocking { try await ParseJob.json(b, url: "x", fetch: m.fetch) }
        XCTAssertEqual(r.headers, ["Referer": "fallback"])
    }

    func testJSONParseRejectsShortUrl() {
        let m = MockFetch()
        m.on("jx", #"{"url":"http://short"}"#)
        XCTAssertThrowsError(try blocking { try await ParseJob.json(Parse(type: 1, url: "http://jx/?u="), url: "x", fetch: m.fetch) })
    }

    func testGodParsePrefersFlagMatchedAndFirstSuccess() throws {
        let m = MockFetch()
        m.on("bad", "{}")
        m.on("good", #"{"url":"\#(long)"}"#)
        var bad = Parse(type: 1, url: "http://bad/?u=", name: "bad")
        bad.flag = ["qq"]
        var good = Parse(type: 1, url: "http://good/?u=", name: "good")
        good.flag = ["qq"]
        let other = Parse(type: 1, url: "http://other/?u=", name: "other")
        let out = try blocking { try await ParseJob.god(url: "x", flag: "qq", parses: [.god, bad, good, other], fetch: m.fetch) }
        XCTAssertEqual(out.from, "good")
        XCTAssertFalse(m.requests.contains { $0.url?.host == "other" })
        XCTAssertThrowsError(try blocking { try await ParseJob.god(url: "x", flag: "qq", parses: [.god, bad], fetch: m.fetch) })
    }

    func testPickHonorsPlayUrlPrefixes() {
        var r = VodResult()
        r.playUrl = "json:http://j/?u="
        XCTAssertEqual(ParseJob.pick(result: r, useParse: false, selected: nil, parses: []).type, 1)
        r.playUrl = "parse:B"
        let p = ParseJob.pick(result: r, useParse: true, selected: .god, parses: [Parse(type: 1, url: "u", name: "B")])
        XCTAssertEqual(p.name, "B")
        r.playUrl = ""
        XCTAssertEqual(ParseJob.pick(result: r, useParse: true, selected: .god, parses: []).type, 4)
        r.playUrl = "http://sniff/?url="
        XCTAssertEqual(ParseJob.pick(result: r, useParse: false, selected: .god, parses: []).url, "http://sniff/?url=")
    }

    func testConfigInsertsGodParseFirst() throws {
        let c = try VodConfig.parse(#"{"parses":[{"name":"A","type":1,"url":"u","ext":{"flag":["qq"],"header":{"User-Agent":"x"}}}]}"#)
        XCTAssertEqual(c.parses.map(\.type), [4, 1])
        XCTAssertEqual(c.parses[1].flag, ["qq"])
        XCTAssertEqual(c.parses[1].header["User-Agent"], "x")
        XCTAssertTrue(try VodConfig.parse("{}").parses.isEmpty)
    }

    func testSkipRules() {
        XCTAssertEqual(PlaybackSkip(opening: 90, ending: 120).start(resume: 0), 90)
        XCTAssertEqual(PlaybackSkip(opening: 90, ending: 0).start(resume: 300), 300)
        XCTAssertTrue(PlaybackSkip(opening: 0, ending: 120).shouldEnd(position: 2890, duration: 3000))
        XCTAssertFalse(PlaybackSkip(opening: 0, ending: 120).shouldEnd(position: 2800, duration: 3000))
        XCTAssertFalse(PlaybackSkip(opening: 0, ending: 0).shouldEnd(position: 2999, duration: 3000))
    }

    func testSnifferRulesAndAds() {
        Sniffer.rules = [SniffRule(hosts: ["api.52wyb.com"], regex: ["m3u8?pt=m3u8"], exclude: ["test.json"])]
        Sniffer.ads = ["ads.example.com"]
        defer { Sniffer.rules = []; Sniffer.ads = [] }
        XCTAssertTrue(Sniffer.isVideoFormat("https://api.52wyb.com/x?m3u8?pt=m3u8"))
        XCTAssertFalse(Sniffer.isVideoFormat("https://api.52wyb.com/test.json/a.m3u8"))
        // 按 url= 参数里的 host 也能命中规则
        XCTAssertEqual(Sniffer.rule(for: "https://jx.example.com/?url=https://api.52wyb.com/p").regex, ["m3u8?pt=m3u8"])
        XCTAssertTrue(Sniffer.isAd("ads.example.com"))
        XCTAssertFalse(Sniffer.isAd("cdn.example.com"))
    }

    func testType0UsesInjectedSniffer() throws {
        let sniff: ParseJob.Sniff = { url, _, click in
            ParseJob.Output(url: "\(url)#\(click)", headers: [:], from: "")
        }
        let out = try blocking {
            try await ParseJob.run(Parse(type: 0, url: "http://jx/?u=", name: "网页"), url: "http://v/1.html", flag: "f",
                                   parses: [], click: "go()", fetch: MockFetch().fetch, sniff: sniff)
        }
        XCTAssertEqual(out.url, "http://jx/?u=http://v/1.html#go()")
        XCTAssertEqual(out.from, "网页")
        XCTAssertThrowsError(try blocking {
            try await ParseJob.run(Parse(type: 0, url: "x"), url: "y", flag: "", parses: [], fetch: MockFetch().fetch, sniff: nil)
        })
    }

    func testGodRacesWebSniffWhenJSONFails() throws {
        let m = MockFetch()
        m.on("bad", "{}")
        let sniff: ParseJob.Sniff = { url, _, _ in
            try await Task.sleep(for: .milliseconds(50))
            return ParseJob.Output(url: url + ".m3u8", headers: [:], from: "")
        }
        let parses = [.god, Parse(type: 1, url: "http://bad/?u=", name: "json"), Parse(type: 0, url: "http://web/?u=", name: "web")]
        let out = try blocking { try await ParseJob.god(url: "x", flag: "f", parses: parses, fetch: m.fetch, sniff: sniff) }
        XCTAssertEqual(out.from, "web")
        XCTAssertEqual(out.url, "http://web/?u=x.m3u8")
    }
}
