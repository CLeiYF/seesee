import Foundation
import JavaScriptCore

/// 注入到 JS 全局的方法，对应 quickjs 的 Global / Local / Console + http.js
extension JSRuntime {
    /// local.get/set/delete 的存储（对应 Prefers，key 规则 cache_<rule>_<key>）
    nonisolated(unsafe) static var store: UserDefaults = .standard

    func install() {
        let ctx = context
        ctx.exceptionHandler = { [weak self] _, e in
            let msg = e?.toString() ?? "unknown"
            let stack = e?.forProperty("stack")?.toString() ?? ""
            self?.setError(stack.isEmpty || stack == "undefined" ? msg : "\(msg)\n\(stack)")
        }
        ctx.setObject(ctx.globalObject, forKeyedSubscript: "globalThis" as NSString)

        // console
        let log: @convention(block) () -> Void = {
            let args = JSContext.currentArguments()?.compactMap { ($0 as? JSValue)?.toString() } ?? []
            print("[js]", args.joined(separator: " "))
        }
        let console = JSValue(newObjectIn: ctx)!
        for k in ["log", "info", "warn", "error", "debug"] { console.setObject(log, forKeyedSubscript: k as NSString) }
        ctx.setObject(console, forKeyedSubscript: "console" as NSString)

        // local
        func key(_ rule: String, _ k: String) -> String { "cache_" + (rule.isEmpty ? "" : rule + "_") + k }
        let local = JSValue(newObjectIn: ctx)!
        let get: @convention(block) (String, String) -> String = { Self.store.string(forKey: key($0, $1)) ?? "" }
        let set: @convention(block) (String, String, JSValue) -> Void = { Self.store.set($2.toString(), forKey: key($0, $1)) }
        let del: @convention(block) (String, String) -> Void = { Self.store.removeObject(forKey: key($0, $1)) }
        local.setObject(get, forKeyedSubscript: "get" as NSString)
        local.setObject(set, forKeyedSubscript: "set" as NSString)
        local.setObject(del, forKeyedSubscript: "delete" as NSString)
        ctx.setObject(local, forKeyedSubscript: "local" as NSString)

        // 工具函数
        let s2t: @convention(block) (String) -> String = { $0.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? $0 }
        let t2s: @convention(block) (String) -> String = { $0.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? $0 }
        let joinUrl: @convention(block) (String, String) -> String = { ConfigDecoder.resolve($0, $1) }
        let md5X: @convention(block) (String) -> String = { JSCrypto.md5($0) }
        let aesX: @convention(block) (String, Bool, String, Bool, String, JSValue, Bool) -> String = { mode, enc, input, inB64, key, iv, outB64 in
            JSCrypto.aes(mode: mode, encrypt: enc, input: input, inBase64: inB64, key: key,
                         iv: iv.isNull || iv.isUndefined ? nil : iv.toString(), outBase64: outB64)
        }
        let rsaX: @convention(block) (String, Bool, Bool, String, Bool, String, Bool) -> String = { _, pub, enc, input, inB64, key, outB64 in
            JSCrypto.rsa(pub: pub, encrypt: enc, input: input, inBase64: inB64, key: key, outBase64: outB64)
        }
        // 本地代理（对应 Global.getProxy / js2Proxy）；siteKey 让 /proxy 找回对应爬虫
        let key = siteKey
        let getProxy: @convention(block) (Bool) -> String = { _ in LocalServer.shared.proxyURL + "?do=js&siteKey=" + HTTP.encode(key) }
        let getPort: @convention(block) () -> Int = { Int(LocalServer.shared.port) }
        let js2Proxy: @convention(block) (Bool, Int, String, String, JSValue) -> String = { _, type, sk, url, headers in
            let h = headers.isObject ? (headers.context.objectForKeyedSubscript("JSON").invokeMethod("stringify", withArguments: [headers]).toString() ?? "{}") : "{}"
            return LocalServer.shared.proxyURL + "?do=js&from=catvod&siteType=\(type)&siteKey=\(HTTP.encode(sk))&header=\(HTTP.encode(h))&url=\(HTTP.encode(url))"
        }
        ctx.setObject(js2Proxy, forKeyedSubscript: "js2Proxy" as NSString)
        let setTimeout: @convention(block) (JSValue, JSValue) -> Void = { [weak self] fn, delay in
            let ms = delay.isUndefined ? 0 : delay.toDouble()
            self?.schedule(ms / 1000) { fn.call(withArguments: []) }
        }
        for (name, fn) in [("s2t", s2t), ("t2s", t2s), ("joinUrl", joinUrl), ("md5X", md5X), ("aesX", aesX),
                           ("rsaX", rsaX), ("getProxy", getProxy), ("getPort", getPort), ("setTimeout", setTimeout)] as [(String, Any)] {
            ctx.setObject(fn, forKeyedSubscript: name as NSString)
        }

        // _http(url, options)：有 complete 回调走异步，否则同步返回 {code, headers, content}
        let http: @convention(block) (String, JSValue) -> JSValue? = { [weak self] url, options in
            guard let self else { return nil }
            let req = JSRequest(options)
            let complete = options.forProperty("complete")
            if let complete, complete.isObject {
                DispatchQueue.global().async {
                    let res = req.send(url, session: self.session)
                    self.schedule(0) { complete.call(withArguments: [res.value(in: self.context)]) }
                }
                return nil
            }
            return req.send(url, session: self.session).value(in: self.context)
        }
        ctx.setObject(http, forKeyedSubscript: "_http" as NSString)

        // http.js：req(url, opt) 同步、http(url, opt) 返回 Promise
        if let file = Bundle.main.url(forResource: "lib/http", withExtension: "js", subdirectory: "js"),
           let code = try? String(contentsOf: file, encoding: .utf8) {
            ctx.evaluateScript(code)
        } else {
            ctx.evaluateScript(Self.httpJS)
        }
        // 模块 import 入口
        let imp: @convention(block) (String) -> JSValue? = { [weak self] url in
            guard let self else { return nil }
            do { return try self.module(url) } catch {
                self.context.exception = JSValue(newErrorFromMessage: error.localizedDescription, in: self.context)
                return nil
            }
        }
        ctx.setObject(imp, forKeyedSubscript: "__import" as NSString)
    }

    /// 测试环境没有 app bundle 时的兜底（与资源里的 http.js 相同）
    static let httpJS = """
    let req = (url, options) => http(url, Object.assign({ async: false }, options));
    function http(url, options = {}) {
        if (options?.async === false) return _http(url, options)
        return new Promise(resolve => _http(url, Object.assign({ complete: res => resolve(res) }, options)))
            .catch(err => ({ ok: false, status: 500, url }))
    }
    """
}

/// 对应 quickjs/bean/Req + utils/Connect
struct JSRequest {
    var method = "get"
    var headers: [String: String] = [:]
    var body: String?
    var data: Any?
    var postType = "json"
    var buffer = 0
    var timeout: TimeInterval = 10
    var redirect = true

    init(_ o: JSValue) {
        func s(_ k: String) -> String? {
            guard let v = o.forProperty(k), !v.isUndefined, !v.isNull else { return nil }
            return v.toString()
        }
        method = (s("method") ?? "get").lowercased()
        if let h = o.forProperty("headers")?.toDictionary() as? [String: Any] { headers = h.mapValues { "\($0)" } }
        body = s("body")
        if let d = o.forProperty("data"), !d.isUndefined, !d.isNull { data = d.isString ? d.toString() : d.toObject() }
        postType = s("postType") ?? "json"
        buffer = Int(s("buffer") ?? "0") ?? 0
        timeout = (Double(s("timeout") ?? "") ?? 10000) / 1000
        redirect = (Int(s("redirect") ?? "1") ?? 1) == 1
    }

    struct Response {
        var code: Int?
        var headers: [String: String] = [:]
        var data = Data()
        var buffer = 0
        var charset = String.Encoding.utf8

        func value(in ctx: JSContext) -> JSValue {
            let o = JSValue(newObjectIn: ctx)!
            o.setObject(code.map { $0 as Any } ?? "", forKeyedSubscript: "code" as NSString)
            o.setObject(headers, forKeyedSubscript: "headers" as NSString)
            switch buffer {
            case 1: o.setObject(data.map { Int(Int8(bitPattern: $0)) }, forKeyedSubscript: "content" as NSString)
            case 2: o.setObject(data.base64EncodedString(), forKeyedSubscript: "content" as NSString)
            default: o.setObject(String(data: data, encoding: charset) ?? HTTP.string(data), forKeyedSubscript: "content" as NSString)
            }
            return o
        }
    }

    func send(_ url: String, session: URLSession) -> Response {
        var res = Response(buffer: buffer)
        guard let u = URL(string: url) ?? URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else { return res }
        var r = HTTP.request(u, headers: headers, timeout: timeout)
        if let ct = headers.first(where: { $0.key.lowercased() == "content-type" })?.value,
           let cs = ct.split(separator: ";").first(where: { $0.contains("charset=") })?.split(separator: "=").last,
           String(cs).lowercased().contains("gb") {
            res.charset = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        }
        switch method {
        case "post":
            r.httpMethod = "POST"
            setBody(&r)
        case "header", "head":
            r.httpMethod = "HEAD"
        case "get": break
        default: // PUT / DELETE / PROPFIND（WebDAV）等
            r.httpMethod = method.uppercased()
            setBody(&r)
        }
        let s = redirect ? session : URLSession(configuration: .default, delegate: NoRedirect(), delegateQueue: nil)
        guard let (data, http) = try? syncFetch(s, r) else { return res }
        res.code = http?.statusCode
        res.data = data
        for (k, v) in http?.allHeaderFields ?? [:] { res.headers["\(k)"] = "\(v)" }
        return res
    }

    private func setBody(_ r: inout URLRequest) {
        if let data {
            switch postType {
            case "form", "form-data":
                let map = (data as? [String: Any]) ?? [:]
                r.httpBody = map.map { "\(HTTP.encode($0.key))=\(HTTP.encode("\($0.value)"))" }.joined(separator: "&").data(using: .utf8)
                r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            default:
                if let s = data as? String { r.httpBody = Data(s.utf8) }
                else { r.httpBody = try? JSONSerialization.data(withJSONObject: data) }
                r.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            }
        } else if let body {
            r.httpBody = Data(body.utf8)
        }
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}
