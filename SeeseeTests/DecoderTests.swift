import XCTest
@testable import Seesee

final class DecoderTests: XCTestCase {
    let base = "http://h.com/a/b/c.json"

    func testPlainJSONPassThrough() throws {
        XCTAssertEqual(try ConfigDecoder.verify(url: base, data: #"{"sites":[]}"#), #"{"sites":[]}"#)
    }

    func testBase64Marker() throws {
        XCTAssertEqual(try ConfigDecoder.verify(url: base, data: "garbage abcd1234**eyJhIjoxfQ=="), #"{"a":1}"#)
    }

    func testAES() throws {
        // openssl aes-128-cbc，key=abcdefgh00000000，iv=1234567890abc000，明文 {"sites":[]}
        let data = "242361626364656667682324f884ae78eab2f3537760fbd0dedfa0d231323334353637383930616263"
        XCTAssertEqual(try ConfigDecoder.verify(url: base, data: data), #"{"sites":[]}"#)
    }

    func testEmptyThrows() {
        XCTAssertThrowsError(try ConfigDecoder.verify(url: base, data: ""))
    }

    func testRelativePaths() {
        let out = ConfigDecoder.fix(url: base, data: #"{"a":"./x.jar","b":"../y.json"}"#)
        XCTAssertEqual(out, #"{"a":"http://h.com/a/b/x.jar","b":"http://h.com/a/y.json"}"#)
    }

    func testRelativeJSWithQueryKeepsInnerRelatives() {
        let out = ConfigDecoder.fix(url: base, data: #"{"api":"./lib/drpy.js?a=./b"}"#)
        XCTAssertEqual(out, #"{"api":"http://h.com/a/b/lib/drpy.js?a=./b"}"#)
    }
}
