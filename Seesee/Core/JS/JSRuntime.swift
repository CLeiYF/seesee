import Foundation
import JavaScriptCore

/// 一个 JSContext + 一条专用线程（对应 quickjs Spider 的单线程 executor）。
/// 所有 JS 调用都通过 `perform` 串行执行；`req` 同步请求会阻塞该线程，与原项目一致。
final class JSRuntime: @unchecked Sendable {
    enum Failure: LocalizedError {
        case script(String)
        case timeout
        var errorDescription: String? {
            switch self {
            case .script(let m): "JS 错误：\(m)"
            case .timeout: "JS 执行超时"
            }
        }
    }

    let context: JSContext
    private let thread: Thread
    private let runLoop: RunLoop
    let session: URLSession
    private var modules: [String: JSValue] = [:]
    private var lastError: String?
    /// 模块源码加载：url → 源码（测试可注入）
    var source: (String) throws -> String

    init(session: URLSession = .shared, source: ((String) throws -> String)? = nil) {
        self.session = session
        self.source = source ?? JSRuntime.defaultSource(session)
        var loop: RunLoop?
        let ready = DispatchSemaphore(value: 0)
        thread = Thread {
            loop = RunLoop.current
            RunLoop.current.add(Port(), forMode: .default)
            ready.signal()
            while !Thread.current.isCancelled { RunLoop.current.run(mode: .default, before: .distantFuture) }
        }
        thread.name = "seesee.js"
        thread.stackSize = 8 << 20
        thread.start()
        ready.wait()
        runLoop = loop!
        context = JSContext()
        try? perform { self.install() }
    }

    deinit { thread.cancel() }

    // MARK: 线程调度

    /// 在 JS 线程同步执行
    func perform<T>(_ body: @escaping () throws -> T) throws -> T {
        if Thread.current == thread { return try body() }
        var result: Swift.Result<T, Error>!
        let done = DispatchSemaphore(value: 0)
        runLoop.perform {
            result = Swift.Result { try body() }
            done.signal()
        }
        CFRunLoopWakeUp(runLoop.getCFRunLoop())
        done.wait()
        return try result.get()
    }

    /// JSValue → 字符串；必须在 JS 线程调用
    func text(_ v: JSValue?) -> String? {
        guard let v, !v.isUndefined, !v.isNull else { return nil }
        if v.isString || v.isNumber || v.isBoolean { return v.toString() }
        let json = context.objectForKeyedSubscript("JSON")?.invokeMethod("stringify", withArguments: [v])
        return json.flatMap { $0.isUndefined ? nil : $0.toString() }
    }

    /// setTimeout / 异步回调：延迟后回到 JS 线程执行
    func schedule(_ delay: TimeInterval, _ body: @escaping () -> Void) { post(after: delay, body) }

    /// 由 exceptionHandler 调用（已在 JS 线程上）
    func setError(_ message: String) { lastError = message }

    /// 在 JS 线程异步执行（回调、定时器）
    private func post(after delay: TimeInterval = 0, _ body: @escaping () -> Void) {
        if delay <= 0 {
            runLoop.perform(body)
            CFRunLoopWakeUp(runLoop.getCFRunLoop())
        } else {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in self?.post(body) }
        }
    }

    // MARK: 执行

    @discardableResult
    func evaluate(_ code: String, url: String = "inline.js") throws -> JSValue {
        try perform {
            self.lastError = nil
            let v = self.context.evaluateScript(code, withSourceURL: URL(string: url))
            if let e = self.lastError { throw Failure.script(e) }
            return v ?? JSValue(undefinedIn: self.context)
        }
    }

    /// 调用 obj[name](...args)，若返回 Promise 则在 JS 线程上等它完成。
    /// 结果在 JS 线程上转成字符串（对象走 JSON.stringify），undefined/null 为 nil
    func call(_ obj: JSValue, _ name: String, _ args: [Any], timeout: TimeInterval = 30) async throws -> String? {
        try await withCheckedThrowingContinuation { cont in
            post {
                self.lastError = nil
                guard let fn = obj.forProperty(name), fn.isObject else { return cont.resume(returning: nil) }
                let v = obj.invokeMethod(name, withArguments: args)
                if let e = self.lastError { return cont.resume(throwing: Failure.script(e)) }
                guard let v, v.isObject, let then = v.forProperty("then"), then.isObject else { return cont.resume(returning: self.text(v)) }
                var finished = false
                let finish: (Swift.Result<String?, Error>) -> Void = { r in
                    guard !finished else { return }
                    finished = true
                    cont.resume(with: r)
                }
                let ok: @convention(block) (JSValue) -> Void = { finish(.success(self.text($0))) }
                let fail: @convention(block) (JSValue) -> Void = { finish(.failure(Failure.script($0.toString() ?? "rejected"))) }
                v.invokeMethod("then", withArguments: [JSValue(object: ok, in: self.context)!, JSValue(object: fail, in: self.context)!])
                self.post(after: timeout) { finish(.failure(Failure.timeout)) }
            }
            CFRunLoopWakeUp(self.runLoop.getCFRunLoop())
        }
    }

    // MARK: 模块

    /// 加载（并缓存）一个 ES module，返回其导出对象
    func module(_ url: String) throws -> JSValue {
        try perform {
            if let m = self.modules[url] { return m }
            let code = try self.source(url)
            let wrapped = JSModule.transform(code) { ConfigDecoder.resolve(url, $0) }
            let exports = JSValue(newObjectIn: self.context)!
            self.modules[url] = exports // 先占位，避免循环 import 死循环
            self.lastError = nil
            let fn = self.context.evaluateScript(wrapped, withSourceURL: URL(string: url))
            if let e = self.lastError { self.modules[url] = nil; throw Failure.script("\(url): \(e)") }
            fn?.call(withArguments: [exports])
            if let e = self.lastError { self.modules[url] = nil; throw Failure.script("\(url): \(e)") }
            return exports
        }
    }

    /// assets://js/lib/x.js 与 lib/x.js 读包内资源；http(s) 走网络
    static func defaultSource(_ session: URLSession) -> (String) throws -> String {
        { url in
            if let path = bundledPath(url) {
                guard let file = Bundle.main.url(forResource: path, withExtension: nil, subdirectory: "js"),
                      let s = try? String(contentsOf: file, encoding: .utf8) else { throw URLError(.fileDoesNotExist) }
                return s
            }
            if url.hasPrefix("file://"), let u = URL(string: url) { return try String(contentsOf: u, encoding: .utf8) }
            let (data, _) = try syncFetch(session, try HTTP.get(url))
            return HTTP.string(data)
        }
    }

    static func bundledPath(_ url: String) -> String? {
        for prefix in ["assets://js/", "assets:///js/", "lib/"] where url.hasPrefix(prefix) {
            return prefix == "lib/" ? url : String(url.dropFirst(prefix.count))
        }
        if let r = url.range(of: "/js/lib/"), url.hasPrefix("assets") { return "lib/" + url[r.upperBound...] }
        return nil
    }
}

/// 同步网络请求（JS 线程内的 req 是同步语义）
func syncFetch(_ session: URLSession, _ request: URLRequest) throws -> (Data, HTTPURLResponse?) {
    var out: Swift.Result<(Data, HTTPURLResponse?), Error>!
    let done = DispatchSemaphore(value: 0)
    session.dataTask(with: request) { d, r, e in
        out = e.map { .failure($0) } ?? .success((d ?? Data(), r as? HTTPURLResponse))
        done.signal()
    }.resume()
    done.wait()
    return try out.get()
}
