import JavaScriptCore
import XCTest
@testable import Seesee

final class JSTests: XCTestCase {
    /// 内存里的"网络"：url → 源码
    private func runtime(_ files: [String: String]) -> JSRuntime {
        JSRuntime { url in
            if let s = files[url] { return s }
            if let p = JSRuntime.bundledPath(url) {
                // 测试 bundle 里没有 app 资源，直接读仓库里的文件
                let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                return try String(contentsOf: root.appending(path: "Seesee/Resources/js/\(p)"), encoding: .utf8)
            }
            throw URLError(.fileDoesNotExist)
        }
    }

    func testModuleTransformCoversCommonForms() throws {
        let rt = runtime([
            "http://h/a/dep.js": "export const x = 1; export default function d() { return 2 }; const y = 3; export { y as z };",
            "http://h/a/main.js": """
            import d, { x, z as w } from './dep.js';
            import * as ns from './dep.js';
            export function sum() { return d() + x + w + ns.x }
            export default { name: 'm' }
            """,
        ])
        let m = try rt.module("http://h/a/main.js")
        XCTAssertEqual(try rt.perform { m.forProperty("sum").call(withArguments: []).toInt32() }, 7)
        XCTAssertEqual(try rt.perform { m.forProperty("default").forProperty("name").toString() }, "m")
    }

    func testModuleSyntaxErrorThrows() {
        let rt = runtime(["http://h/bad.js": "export function ("])
        XCTAssertThrowsError(try rt.module("http://h/bad.js"))
    }

    func testCrypto() {
        XCTAssertEqual(JSCrypto.md5("hello"), "5d41402abc4b2a76b9719d911017c592")
        // openssl aes-128-cbc key=1234567890123456 iv=abcdefghijklmnop
        XCTAssertEqual(JSCrypto.aes(mode: "AES/CBC/PKCS5", encrypt: true, input: "hello", inBase64: false,
                                    key: "1234567890123456", iv: "abcdefghijklmnop", outBase64: true), "ZM6V+N4TrIblhrpN+FfkYw==")
        XCTAssertEqual(JSCrypto.aes(mode: "AES/CBC/PKCS5", encrypt: false, input: "ZM6V+N4TrIblhrpN+FfkYw==", inBase64: true,
                                    key: "1234567890123456", iv: "abcdefghijklmnop", outBase64: false), "hello")
        // ECB，key 不足 16 字节补 0
        XCTAssertEqual(JSCrypto.aes(mode: "AES/ECB/PKCS5", encrypt: true, input: "hello", inBase64: false,
                                    key: "key", iv: nil, outBase64: true), "XicFC1nIif7p+VMTclm/aw==")
        XCTAssertEqual(JSCrypto.aes(mode: "AES/CBC/PKCS5", encrypt: false, input: "!!", inBase64: true,
                                    key: "k", iv: "v", outBase64: false), "")
    }

    func testRSARoundTripAndPrivateSignVector() {
        let enc = JSCrypto.rsa(pub: true, encrypt: true, input: "hello", inBase64: false, key: Self.pub, outBase64: true)
        XCTAssertFalse(enc.isEmpty)
        XCTAssertEqual(JSCrypto.rsa(pub: false, encrypt: false, input: enc, inBase64: true, key: Self.priv, outBase64: false), "hello")
        // openssl pkeyutl -sign（PKCS1 type 1），确定性
        let sig = JSCrypto.rsa(pub: false, encrypt: true, input: "hello", inBase64: false, key: Self.priv, outBase64: true)
        XCTAssertEqual(sig, Self.sig)
        XCTAssertEqual(JSCrypto.rsa(pub: true, encrypt: false, input: sig, inBase64: true, key: Self.pub, outBase64: false), "hello")
    }

    func testGlobalsAndLocal() throws {
        JSRuntime.store = UserDefaults(suiteName: "js-test-\(UUID().uuidString)")!
        let rt = runtime([:])
        let v = try rt.evaluate("""
        local.set('r', 'k', 'v1');
        [md5X('hello'), joinUrl('http://h/a/b.js', '../c.js'), local.get('r', 'k'), t2s('電影'), typeof req, typeof http].join('|')
        """)
        XCTAssertEqual(try rt.perform { v.toString() }, "5d41402abc4b2a76b9719d911017c592|http://h/c.js|v1|电影|function|function")
    }

    func testCheerioFromBundledCatJS() throws {
        let rt = runtime([:])
        let m = try rt.module("assets://js/lib/cat.js")
        let v = try rt.perform { () -> String? in
            let load = m.forProperty("load")!
            let fn = rt.context.evaluateScript("(load) => { const $ = load('<ul><li class=a>x</li><li class=a>y</li></ul>'); return $('li.a').map((i, e) => $(e).text()).get().join(',') }")!
            return fn.call(withArguments: [load])?.toString()
        }
        XCTAssertEqual(v, "x,y")
    }

    func testDefaultExportSpiderEndToEnd() async throws {
        let rt = runtime(["http://h/s.js": """
        let ext = '';
        export default {
          init(e) { ext = e.k },
          async home(filter) { return JSON.stringify({ class: [{ type_id: '1', type_name: ext }] }) },
          homeVod() { return { list: [{ vod_id: 'v1', vod_name: 'A' }] } },
          search(wd, quick) { return JSON.stringify({ list: [{ vod_id: wd, vod_name: wd }] }) },
          play(flag, id, flags) { return JSON.stringify({ parse: 0, url: id + '.m3u8' }) },
        }
        """])
        var site = Site(key: "s", api: "http://h/s.js", ext: #"{"k":"电影"}"#, type: 3)
        site.header = ["Referer": "r"]
        let spider = JSSpider(site: site, runtime: rt)
        let home = try await spider.home()
        XCTAssertEqual(home.classes.first?.typeName, "电影")
        XCTAssertEqual(home.list.first?.vodId, "v1")
        let s = try await spider.search("電", quick: false, page: 1)
        XCTAssertEqual(s.list.first?.vodId, "电")
        XCTAssertEqual(s.list.first?.siteKey, "s")
        let p = try await spider.player(flag: "f", id: "http://x/1", vipFlags: [])
        XCTAssertEqual(p.url.v, "http://x/1.m3u8")
        XCTAssertEqual(p.flag, "f")
        XCTAssertEqual(p.header["Referer"], "r")
        // 未实现的方法返回空结果而不是报错
        let d = try await spider.detail(ids: ["1"])
        XCTAssertTrue(d.list.isEmpty)
    }

    func testCatStyleSpiderGetsCfgAndAsyncReq() async throws {
        let rt = runtime(["http://h/c.js": """
        let cfg;
        async function init(c) { cfg = c }
        async function home() {
          const r = await req('http://h/data', {});
          return JSON.stringify({ class: [{ type_id: cfg.skey, type_name: String(cfg.ext.a) + r.content }] });
        }
        export function __jsEvalReturn() { return { init, home } }
        """])
        // _http 走真实网络会失败，这里替换成本地实现
        try rt.perform {
            let fake: @convention(block) (String, JSValue) -> JSValue? = { _, opt in
                let res = JSValue(object: ["code": 200, "content": "!"], in: rt.context)!
                if let c = opt.forProperty("complete"), c.isObject { c.call(withArguments: [res]); return nil }
                return res
            }
            rt.context.setObject(fake, forKeyedSubscript: "_http" as NSString)
        }
        let spider = JSSpider(site: Site(key: "cat", api: "http://h/c.js", ext: #"{"a":1}"#, type: 3), runtime: rt)
        let home = try await spider.home()
        XCTAssertEqual(home.classes.first?.typeId, "cat")
        XCTAssertEqual(home.classes.first?.typeName, "1!")
    }

    func testMethodsKeepThis() async throws {
        let rt = runtime(["http://h/t.js": "export default { n: 'T', home() { return JSON.stringify({ class: [{ type_id: '1', type_name: this.n }] }) } }"])
        let spider = JSSpider(site: Site(key: "t", api: "http://h/t.js", type: 3), runtime: rt)
        let home = try await spider.home()
        XCTAssertEqual(home.classes.first?.typeName, "T")
    }

    func testScriptErrorSurfaces() async {
        let rt = runtime(["http://h/e.js": "export default { home() { throw new Error('boom') } }"])
        let spider = JSSpider(site: Site(key: "e", api: "http://h/e.js", type: 3), runtime: rt)
        do {
            _ = try await spider.home()
            XCTFail("should throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("boom"), error.localizedDescription)
        }
    }

    // 测试用 RSA-1024 密钥（仅测试）
    static let pub = """
    -----BEGIN PUBLIC KEY-----
    MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC28F/hDdGV1zjCekGbjVPmn80B
    2Qm5J7P1XdO95Dx94keEN65JxA+t8qedNuxtnUK3PibZVhSw8DBcvk2+MgOcDOPz
    23RDELtsUnwRuUvLI3VSTcIsA6zT2SKYsWVv42PNh0OsdiFA3s4aXg7wSirxgwe6
    BxOuLKry4/pGngZADwIDAQAB
    -----END PUBLIC KEY-----
    """
    static let priv = """
    -----BEGIN PRIVATE KEY-----
    MIICeAIBADANBgkqhkiG9w0BAQEFAASCAmIwggJeAgEAAoGBALbwX+EN0ZXXOMJ6
    QZuNU+afzQHZCbkns/Vd073kPH3iR4Q3rknED63yp5027G2dQrc+JtlWFLDwMFy+
    Tb4yA5wM4/PbdEMQu2xSfBG5S8sjdVJNwiwDrNPZIpixZW/jY82HQ6x2IUDezhpe
    DvBKKvGDB7oHE64sqvLj+kaeBkAPAgMBAAECgYAgueetDxfLQnE4+T37YdD8lOHL
    ztPad6vN3Tcf5VCdBHnewUdAkv5rE9nAWi75fQSOW2P/xVJ2RMGiFbk6qR/T4Sde
    Ikr3JyDD374F76EUq6UvBN9vtrOKBiw0ZSCCrqj1cwlOWX1/LpB3AvyMXy7dTX0U
    X+HjbRFBcPaa2rds4QJBAOjmcnvsRTDt60lebAcyXb585VIDPJJ/OCd2wUnF8mpH
    nrj6nIGzC/8Ly0t+2xpIdvdHNlAaofzm6fTmiEzSPlMCQQDJFV2Gz6sHMiTg5Z/O
    xN+fRkbbdoQNRmXEOfp8vXPiMMsPpQDe8ppG6vnWp9qWF3wcQFfCtvHVAJh53OWB
    R2fVAkEAtiKiHW+knKMzgekpqmclELczz3Ngh2CeVZ51gnAfKCZiZl72zidrlkVu
    8td+GYvaHX+/Zd2uGM2s4Sz4Iru4qQJBAINO/GAIRDrSt9pUmGLBlPXBQowVfG3e
    xp247qV+YaoXCsMQkN0Ft1EQKE3QFqFkfJtGOQjhxlG9rdQGN6iQJHECQQC9zmAV
    OwAsWNyt9vLh0h8uFKsFY/Yi5ztvVBqg3fxwN4SM+1Kt1pv+Raj64/DX7qk8G/OL
    kNaqHc6Z7OFtKxWe
    -----END PRIVATE KEY-----
    """
    static let sig = "Po6b8TbjXWuawJPC/HoOlnR2gxJmrXTX75kkABgIfHZD84a5cD5zV9wBnyreWx7tkSp0mXbxF2QsszD+4yanLp704tp/qKqbWWEKKLwUkPu45TbrATzxEk2H/+ifArZYRmf3CoZBEgcgU/KBFUY5CtgvsFti1gkwFwL2JPpaOYY="
}
