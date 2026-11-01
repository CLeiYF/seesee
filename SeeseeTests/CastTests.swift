import XCTest
@testable import Seesee

final class CastTests: XCTestCase {
    func testSSDPLocation() {
        let r = "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nLocation: http://192.168.1.9:49152/desc.xml\r\nST: urn:schemas-upnp-org:service:AVTransport:1\r\n\r\n"
        XCTAssertEqual(DLNA.location(r), "http://192.168.1.9:49152/desc.xml")
        XCTAssertNil(DLNA.location("HTTP/1.1 200 OK\r\n\r\n"))
    }

    func testDescribeFindsAVTransportControl() throws {
        let xml = """
        <root><device><friendlyName>客厅电视</friendlyName><serviceList>
        <service><serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType><controlURL>/rc</controlURL></service>
        <service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType><controlURL>/upnp/av/control</controlURL></service>
        </serviceList></device></root>
        """
        let r = try DLNA.parse(xml, location: "http://192.168.1.9:49152/desc.xml")
        XCTAssertEqual(r.name, "客厅电视")
        XCTAssertEqual(r.control, "http://192.168.1.9:49152/upnp/av/control")
        XCTAssertThrowsError(try DLNA.parse("<root><friendlyName>x</friendlyName></root>", location: "http://h/"))
    }

    func testCastSendsSetURIThenPlay() throws {
        let m = MockFetch()
        m.on("control", "<ok/>")
        let r = DLNA.Renderer(name: "tv", location: "http://h/d.xml", control: "http://h/control")
        try blocking { try await DLNA.cast("http://v/a.m3u8?x=1&y=2", title: "A&B", to: r, fetch: m.fetch) }
        XCTAssertEqual(m.requests.count, 2)
        let first = HTTP.string(m.requests[0].httpBody ?? Data())
        XCTAssertEqual(m.requests[0].value(forHTTPHeaderField: "SOAPAction"), "\"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI\"")
        XCTAssertTrue(first.contains("<CurrentURI>http://v/a.m3u8?x=1&amp;y=2</CurrentURI>"))
        XCTAssertTrue(first.contains("A&amp;amp;B"))   // 标题在 DIDL 里转义一次，DIDL 整体再转义一次
        XCTAssertTrue(HTTP.string(m.requests[1].httpBody ?? Data()).contains("<u:Play"))
    }

    func testDevicePushAgainstLocalServer() throws {
        // 用本 App 的本地服务模拟一台影视设备
        let server = LocalServer.shared
        server.route("/device") { _ in .text(#"{"name":"测试盒子","type":0}"#) }
        nonisolated(unsafe) var pushed = ""
        server.route("/action") { req in pushed = req.query["url"] ?? ""; return .text("OK") }
        let port = server.start()
        let base = "http://127.0.0.1:\(port)"
        let d = try blocking { try await DevicePush.probe(base, fetch: HTTP.live) }
        XCTAssertEqual(d.name, "测试盒子")
        XCTAssertEqual(d.kind, "电视")
        XCTAssertEqual(d.ip, base)
        try blocking { try await DevicePush.push("http://v/1.m3u8", to: d) }
        XCTAssertEqual(pushed, "http://v/1.m3u8")
        XCTAssertNotNil(DevicePush.localIP())
    }
}
