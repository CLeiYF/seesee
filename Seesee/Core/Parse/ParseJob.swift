import Foundation

/// 对应 player/ParseJob.java：type 0（网页嗅探）、1（JSON 解析）、4（超级解析：JSON 与网页嗅探并发，取最先成功）。
/// type 2/3 依赖 jar，iOS 不支持。
enum ParseJob {
    /// 网页嗅探：(页面地址, 请求头, click 脚本) → 嗅探到的视频地址。由 UI 层用 WKWebView 实现并注入，Core 不依赖 WebKit
    typealias Sniff = @Sendable (_ url: String, _ headers: [String: String], _ click: String) async throws -> Output

    struct Output: Equatable {
        var url: String
        var headers: [String: String]
        var from: String
    }

    enum Failure: LocalizedError {
        case failed, unsupported(Int), message(String)
        var errorDescription: String? {
            switch self {
            case .failed: "解析失败"
            case .unsupported(let t): "iOS 暂不支持该解析类型（type \(t)）"
            case .message(let m): m
            }
        }
    }

    static let timeout: TimeInterval = 15

    /// 选择解析：playUrl 为 `json:<url>` / `parse:<name>` 时优先，否则用选中的解析；都没有则把 playUrl 当嗅探地址
    static func pick(result: VodResult, useParse: Bool, selected: Parse?, parses: [Parse]) -> Parse {
        var p: Parse?
        if useParse { p = selected }
        if result.playUrl.hasPrefix("json:") { p = Parse(type: 1, url: String(result.playUrl.dropFirst(5))) }
        if result.playUrl.hasPrefix("parse:") { p = parses.first { $0.name == String(result.playUrl.dropFirst(6)) } }
        var parse = p.flatMap { $0.type == 0 && $0.url.isEmpty ? nil : $0 } ?? Parse(type: 0, url: result.playUrl)
        if parse.header.isEmpty { parse.header = result.header }
        return parse
    }

    static func run(_ parse: Parse, url: String, flag: String, parses: [Parse], click: String = "",
                    fetch: @escaping HTTP.Fetch, sniff: Sniff?) async throws -> Output {
        switch parse.type {
        case 0:
            guard let sniff else { throw Failure.unsupported(0) }
            var out = try await sniff(parse.url + url, parse.header, click)
            out.from = parse.name
            return out
        case 1:
            return try await json(parse, url: url, fetch: fetch)
        case 4:
            return try await god(url: url, flag: flag, parses: parses, fetch: fetch, sniff: sniff)
        default:
            throw Failure.unsupported(parse.type)
        }
    }

    /// GET parse.url + url，取 url 或 data.url；长度不足 40 视为失败（与原项目一致）
    static func json(_ parse: Parse, url: String, fetch: HTTP.Fetch) async throws -> Output {
        let req = try HTTP.get(parse.url + url, headers: parse.header, timeout: timeout)
        let obj = (try? JSONDecoder().decode(AnyJSON.self, from: try await fetch(req)))?.value as? [String: Any] ?? [:]
        var u = AnyJSON(raw: obj["url"] ?? "").string
        if u.isEmpty, let data = obj["data"] as? [String: Any] { u = AnyJSON(raw: data["url"] ?? "").string }
        guard u.count > 40 else { throw Failure.failed }
        return Output(url: u, headers: headers(obj, fallback: parse.header), from: parse.name)
    }

    /// 按 flag 过滤某类解析，没有匹配就用该类全部（对应 VodConfig.getParses(type, flag)）
    static func parses(_ all: [Parse], type: Int, flag: String) -> [Parse] {
        let items = all.filter { $0.type == type }
        let matched = items.filter { $0.flag.contains(flag) }
        return matched.isEmpty ? items : matched
    }

    /// 并发跑匹配 flag 的所有 JSON 解析与网页解析，第一个成功即返回
    static func god(url: String, flag: String, parses all: [Parse], fetch: @escaping HTTP.Fetch, sniff: Sniff? = nil) async throws -> Output {
        let json = parses(all, type: 1, flag: flag)
        let webs = sniff == nil ? [] : parses(all, type: 0, flag: flag)
        let count = json.count + webs.count
        guard count > 0 else { throw Failure.failed }
        return try await withThrowingTaskGroup(of: Output?.self) { group in
            for p in json { group.addTask { try? await Self.json(p, url: url, fetch: fetch) } }
            if let sniff {
                for p in webs {
                    group.addTask {
                        guard var out = try? await sniff(p.url + url, p.header, "") else { return nil }
                        out.from = p.name
                        return out
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw Failure.failed
            }
            var pending = count
            defer { group.cancelAll() }
            for try await out in group {
                if let out { return out }
                pending -= 1
                if pending == 0 { break }
            }
            throw Failure.failed
        }
    }

    /// 返回里带 User-Agent/Referer/Cookie/ua 时用它们，否则用解析自带 header
    private static func headers(_ obj: [String: Any], fallback: [String: String]) -> [String: String] {
        var h: [String: String] = [:]
        for (k, v) in obj where !(v is NSNull) {
            switch k.lowercased() {
            case "user-agent", "ua": h["User-Agent"] = AnyJSON(raw: v).string
            case "referer": h["Referer"] = AnyJSON(raw: v).string
            case "cookie": h["Cookie"] = AnyJSON(raw: v).string
            default: break
            }
        }
        return h.isEmpty ? fallback : h
    }
}

extension Parse {
    init(type: Int, url: String, name: String = "") {
        self.type = type
        self.url = url
        self.name = name
    }

    /// 配置有解析时插在最前的超级解析（Parse.god()）
    static let god = Parse(type: 4, url: "", name: "超级解析")
}
