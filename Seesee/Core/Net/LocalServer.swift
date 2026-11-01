import Foundation
import Network

/// 本地 HTTP 服务（对应 server/Server + Nano），只监听 127.0.0.1，端口从 9978 起找空闲。
/// 路由：/proxy（爬虫本地代理）、/cache（local 缓存读写），其余 404。
/// ponytail: 自写 HTTP/1.1 解析，只支持 Content-Length 请求体、响应一次性写完并关闭连接；
/// 大文件流式代理（分片视频）需要时改成边读边写
final class LocalServer: @unchecked Sendable {
    struct Request {
        var method: String
        var path: String
        var query: [String: String]
        var headers: [String: String]
        var body: Data
    }

    struct Response {
        var status = 200
        var contentType = "text/plain; charset=utf-8"
        var headers: [String: String] = [:]
        var body = Data()

        static func text(_ s: String, status: Int = 200) -> Response { Response(status: status, body: Data(s.utf8)) }
    }

    typealias Handler = @Sendable (Request) async -> Response?

    static let shared = LocalServer()

    private let queue = DispatchQueue(label: "seesee.server")
    private var listener: NWListener?
    private var handlers: [(prefix: String, handle: Handler)] = []
    private let lock = NSLock()
    private(set) var port: UInt16 = 0

    /// 对应 Proxy.getUrl(true)
    var proxyURL: String { "http://127.0.0.1:\(port)/proxy" }

    /// 对应 UrlUtil.convert：proxy://xxx → http://127.0.0.1:端口/proxy?xxx
    func convert(_ url: String) -> String {
        guard url.lowercased().hasPrefix("proxy://") else { return url }
        return proxyURL + "?" + url.dropFirst("proxy://".count)
    }

    /// 同一前缀重复注册时覆盖
    func route(_ prefix: String, _ handle: @escaping Handler) {
        lock.withLock {
            handlers.removeAll { $0.prefix == prefix }
            handlers.append((prefix, handle))
        }
    }

    /// 同步启动：依次尝试 9978…9998，返回实际端口
    @discardableResult
    func start(from first: UInt16 = 9978) -> UInt16 {
        if port != 0 { return port }
        for p in first..<(first + 21) {
            guard let nwPort = NWEndpoint.Port(rawValue: p) else { continue }
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: nwPort)
            params.allowLocalEndpointReuse = true
            guard let l = try? NWListener(using: params) else { continue }
            let ready = DispatchSemaphore(value: 0)
            var ok = false
            l.stateUpdateHandler = { state in
                switch state {
                case .ready: ok = true; ready.signal()
                case .failed, .cancelled: ready.signal()
                default: break
                }
            }
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.start(queue: queue)
            _ = ready.wait(timeout: .now() + 2)
            if ok {
                listener = l
                port = p
                return p
            }
            l.cancel()
        }
        return 0
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
    }

    /// 监听已失效时重启
    func restartIfNeeded() {
        if let l = listener, case .ready = l.state { return }
        stop()
        start()
    }

    // MARK: - 连接

    private func accept(_ c: NWConnection) {
        c.start(queue: queue)
        receive(c, buffer: Data())
    }

    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, done, error in
            guard let self else { return c.cancel() }
            var buf = buffer
            if let data { buf.append(data) }
            if let req = Self.parse(buf) {
                Task { await self.respond(c, req) }
            } else if done || error != nil || buf.count > 8 << 20 {
                c.cancel()
            } else {
                self.receive(c, buffer: buf)
            }
        }
    }

    private func respond(_ c: NWConnection, _ req: Request) async {
        let routes = lock.withLock { handlers }
        var res = Response.text("Not Found", status: 404)
        if let h = routes.first(where: { req.path.hasPrefix($0.prefix) }) { res = await h.handle(req) ?? res }
        c.send(content: Self.serialize(res), completion: .contentProcessed { _ in c.cancel() })
    }

    // MARK: - HTTP

    /// 请求头完整且 body 达到 Content-Length 时返回请求，否则 nil（继续读）
    static func parse(_ data: Data) -> Request? {
        guard let sep = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<sep.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let first = lines.removeFirst().split(separator: " ")
        guard first.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for l in lines {
            guard let i = l.firstIndex(of: ":") else { continue }
            headers[l[..<i].trimmingCharacters(in: .whitespaces).lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = data[sep.upperBound...]
        guard body.count >= length else { return nil }
        let target = String(first[1])
        let comps = URLComponents(string: "http://x" + target)
        var query: [String: String] = [:]
        for item in comps?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        // POST 表单也并入参数（对应 session.parseBody）
        if headers["content-type"]?.contains("application/x-www-form-urlencoded") == true,
           let form = URLComponents(string: "http://x/?" + String(decoding: body.prefix(length), as: UTF8.self)) {
            for item in form.queryItems ?? [] { query[item.name] = item.value ?? "" }
        }
        return Request(method: String(first[0]), path: comps?.path ?? target, query: query, headers: headers, body: Data(body.prefix(length)))
    }

    static func serialize(_ r: Response) -> Data {
        var head = "HTTP/1.1 \(r.status) \(HTTPURLResponse.localizedString(forStatusCode: r.status).capitalized)\r\n"
        var headers = r.headers
        headers["Content-Type"] = headers["Content-Type"] ?? r.contentType
        headers["Content-Length"] = String(r.body.count)
        headers["Connection"] = "close"
        headers["Access-Control-Allow-Origin"] = "*"
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + r.body
    }
}
