import Foundation
import XCTest
@testable import Seesee

/// 记录请求、按 URL 片段返回固定响应的假网络
final class MockFetch: @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [(String, String)] = []
    private(set) var requests: [URLRequest] = []

    func on(_ contains: String, _ body: String) { routes.append((contains, body)) }

    var fetch: HTTP.Fetch {
        { [self] req in
            lock.lock()
            defer { lock.unlock() }
            requests.append(req)
            let url = req.url?.absoluteString ?? ""
            let body = routes.last { url.contains($0.0) }?.1 ?? "{}"
            return Data(body.utf8)
        }
    }

    var last: URLRequest? { lock.lock(); defer { lock.unlock() }; return requests.last }

    /// 最后一次请求的 query 或 form 参数
    var params: [String: String] {
        guard let req = last else { return [:] }
        let query = req.httpMethod == "POST" ? HTTP.string(req.httpBody ?? Data()) : (req.url?.query ?? "")
        var out: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
            out[kv[0]] = kv.count > 1 ? kv[1] : ""
        }
        return out
    }
}

/// 在同步测试里等待 async 结果（Core 不依赖主线程）
func wait<T>(_ body: @escaping @Sendable () async throws -> T) throws -> T {
    let sem = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var out: Swift.Result<T, Error>!
    Task.detached {
        do { out = .success(try await body()) } catch { out = .failure(error) }
        sem.signal()
    }
    sem.wait()
    return try out.get()
}
