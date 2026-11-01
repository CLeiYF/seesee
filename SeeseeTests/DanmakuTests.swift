import XCTest
@testable import Seesee

final class DanmakuTests: XCTestCase {
    func testXML() {
        let xml = """
        <?xml version="1.0"?><i>
        <d p="12.5,1,25,16777215,1700000000,0,abc,1">第二条 &amp; 转义</d>
        <d p="3.0,5,25,16711680,1700000000,0,abc,2">顶部红色</d>
        <d p="5,7,25,0,0,0,x,3">[高级弹幕]</d>
        <d p="bad">坏数据</d>
        </i>
        """
        let items = DanmakuParser.parse(xml)
        XCTAssertEqual(items.map(\.text), ["顶部红色", "第二条 & 转义"])
        XCTAssertEqual(items[0].kind, .top)
        XCTAssertEqual(items[0].color, 0xFF0000)
        XCTAssertEqual(items[1].kind, .scroll)
        XCTAssertEqual(items[1].time, 12.5)
    }

    func testTXTAndWindow() {
        let txt = "[1,1,25,255]a\n[2,4,25,255]b\n[9,1,25,255]c\nnoise"
        let items = DanmakuParser.parse(txt)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[1].kind, .bottom)
        XCTAssertEqual(DanmakuParser.window(items, from: 1.5, to: 9).map(\.text), ["b"])
        XCTAssertEqual(DanmakuParser.window(items, from: 0, to: 100).count, 3)
    }

    func testResultDanmakuVariants() {
        XCTAssertEqual(VodResult.json(#"{"danmaku":"http://d/1.xml"}"#).danmaku.map(\.url), ["http://d/1.xml"])
        XCTAssertEqual(VodResult.json(#"{"danmaku":"[{\"name\":\"A\",\"url\":\"u1\"}]"}"#).danmaku.first?.name, "A")
        XCTAssertEqual(VodResult.json(#"{"danmaku":[{"url":"u2"}]}"#).danmaku.first?.name, "u2")
        XCTAssertTrue(VodResult.json("{}").danmaku.isEmpty)
    }

    func testLanesNeverOverlapInSameLane() {
        // 0.5 秒一条，同一时刻也有多条
        var items: [DanmakuItem] = []
        for i in 0..<40 { items.append(DanmakuItem(time: Double(i / 2) * 0.5, kind: .scroll, size: 25, color: 0xFFFFFF, text: String(repeating: "弹", count: 3 + i % 5))) }
        items.append(DanmakuItem(time: 1, kind: .top, size: 25, color: 0, text: "顶"))
        items.append(DanmakuItem(time: 1.1, kind: .top, size: 25, color: 0, text: "顶2"))
        let size = CGSize(width: 400, height: 300)
        let lanes = LaneCache.assign(items, size: size, lineHeight: 28, crossing: 8, stay: 4)
        let speed = size.width / 8
        // 同轨道相邻两条：后一条出发时，前一条尾部已进入屏幕（固定速度 → 永远不会追上）
        var last: [Int: DanmakuItem] = [:]
        for (i, d) in items.enumerated() where d.kind == .scroll {
            guard let l = lanes[i] else { continue }
            if let p = last[l] { XCTAssertGreaterThanOrEqual(d.time - p.time, Double(DanmakuOverlay.width(p) / speed) - 1e-9) }
            last[l] = d
        }
        XCTAssertGreaterThan(lanes.compactMap { $0 }.count, 10)
        // 两条顶部弹幕时间重叠 → 不同轨道
        XCTAssertNotEqual(lanes[40], lanes[41])
    }

    func testDanmakuAPIRequestAndSources() throws {
        let r = try XCTUnwrap(DanmakuAPI.request(base: "http://h:9321/", name: "斗破苍穹", episode: "第1集"))
        let c = try XCTUnwrap(URLComponents(url: r.url!, resolvingAgainstBaseURL: false))
        XCTAssertEqual(c.path, "/api/v2/fongmi/danmaku")
        XCTAssertEqual(c.queryItems?.first { $0.name == "name" }?.value, "斗破苍穹")
        XCTAssertEqual(c.queryItems?.first { $0.name == "episode" }?.value, "第1集")
        // 已带接口路径（含 /danmaku 短地址）时不再追加
        XCTAssertEqual(try DanmakuAPI.request(base: "http://h/danmaku", name: "a", episode: "")?.url?.path, "/danmaku")
        XCTAssertNil(try DanmakuAPI.request(base: "", name: "a", episode: ""))
        XCTAssertNil(try DanmakuAPI.request(base: "http://h", name: "", episode: ""))
        let list = DanmakuAPI.sources(Data(#"[{"name":"A - 第1集","url":"http://h/api/v2/comment/1?format=xml"},{"name":"x"}]"#.utf8))
        XCTAssertEqual(list.map(\.url), ["http://h/api/v2/comment/1?format=xml"])
        XCTAssertTrue(DanmakuAPI.sources(Data("oops".utf8)).isEmpty)
    }

    /// danmu_api 实际返回的 XML（截取）能被解析
    func testParsesDanmuAPIXML() throws {
        let xml = """
        <?xml version="1.0" ?>
        <i>
            <d p="0.0,1,25,16777215,1751533608,0,0,19382106282">今天斗破不霸榜 ️♡448</d>
            <d p="12.5,5,25,16711680,1751533608,0,0,1">顶部</d>
        </i>
        """
        let items = DanmakuParser.parse(xml)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.last?.kind, .top)
        XCTAssertEqual(items.last?.color, 0xFF0000)
    }
}
