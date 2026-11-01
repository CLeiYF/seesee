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
}
