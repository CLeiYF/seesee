import Foundation

/// 本地服务的路由（对应 server/process/Proxy + Cache）
enum ServerRoutes {
    static func install(_ server: LocalServer = .shared) {
        // /proxy?do=js&siteKey=…：转给对应 JS 爬虫的 proxy
        server.route("/proxy") { req in
            var params = req.query
            for (k, v) in req.headers where params[k] == nil { params[k] = v }
            guard params["do"] == "js" else { return .text("仅支持 JS 爬虫代理", status: 501) }
            guard let key = params["siteKey"], let spider = JSSpider.find(key) else { return .text("爬虫未加载", status: 404) }
            do {
                let (code, mime, body, headers) = try await spider.proxy(params)
                return LocalServer.Response(status: code, contentType: mime, headers: headers, body: body)
            } catch {
                return .text(error.localizedDescription, status: 500)
            }
        }
        // /cache?do=get|set|del&rule=&key=&value=：与 JS 的 local 共用存储
        server.route("/cache") { req in
            let q = req.query
            let key = "cache_" + ((q["rule"] ?? "").isEmpty ? "" : q["rule"]! + "_") + (q["key"] ?? "")
            switch q["do"] {
            case "get": return .text(JSRuntime.store.string(forKey: key) ?? "")
            case "set": JSRuntime.store.set(q["value"] ?? "", forKey: key)
            case "del": JSRuntime.store.removeObject(forKey: key)
            default: break
            }
            return .text("OK")
        }
    }
}
