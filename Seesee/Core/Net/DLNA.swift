import Foundation
import Network

/// DLNA 投屏（发送端）：SSDP 发现 MediaRenderer → 读设备描述拿 AVTransport controlURL → SOAP SetAVTransportURI + Play。
/// 对应原项目 DLNACastManager 的投屏部分；不实现接收端（iOS 后台无法常驻）。
enum DLNA {
    struct Renderer: Hashable, Identifiable {
        var name: String
        var location: String
        var control: String
        var id: String { location }
    }

    enum Failure: LocalizedError {
        case noTransport, soap(Int, String)
        var errorDescription: String? {
            switch self {
            case .noTransport: "设备不支持 AVTransport"
            case .soap(let c, let m): "投屏失败（\(c)）\(m)"
            }
        }
    }

    static let avTransport = "urn:schemas-upnp-org:service:AVTransport:1"

    // MARK: - 发现

    /// 组播 M-SEARCH，收集 timeout 秒内回复的设备，读取描述后返回
    static func discover(timeout: TimeInterval = 3, fetch: @escaping HTTP.Fetch = HTTP.live) async -> [Renderer] {
        let locations = await search(timeout: timeout)
        return await withTaskGroup(of: Renderer?.self) { g in
            for l in locations { g.addTask { try? await describe(l, fetch: fetch) } }
            var out: [Renderer] = []
            for await r in g { if let r, !out.contains(r) { out.append(r) } }
            return out.sorted { $0.name < $1.name }
        }
    }

    /// 返回 LOCATION 列表
    private static func search(timeout: TimeInterval) async -> [String] {
        await withCheckedContinuation { cont in
            // 所有回调都在这条串行队列上，found/finished 不会并发访问
            let queue = DispatchQueue(label: "seesee.ssdp")
            nonisolated(unsafe) var found = Set<String>()
            nonisolated(unsafe) var finished = false
            guard let group = try? NWMulticastGroup(for: [.hostPort(host: "239.255.255.250", port: 1900)]) else { return cont.resume(returning: []) }
            let conn = NWConnectionGroup(with: group, using: .udp)
            conn.setReceiveHandler(maximumMessageSize: 65535, rejectOversizedMessages: false) { _, data, _ in
                guard let data, let loc = location(String(decoding: data, as: UTF8.self)) else { return }
                found.insert(loc)
            }
            let finish: @Sendable () -> Void = {
                guard !finished else { return }
                finished = true
                conn.cancel()
                cont.resume(returning: Array(found))
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let msg = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: \(avTransport)\r\n\r\n"
                    // 发两次，UDP 可能丢包
                    for _ in 0..<2 { conn.send(content: Data(msg.utf8)) { _ in } }
                case .failed, .cancelled: queue.async(execute: finish)
                default: break
                }
            }
            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout, execute: finish)
        }
    }

    /// 从 SSDP 回复里取 LOCATION 头
    static func location(_ response: String) -> String? {
        for line in response.components(separatedBy: "\r\n") {
            let p = line.split(separator: ":", maxSplits: 1)
            if p.count == 2, p[0].trimmingCharacters(in: .whitespaces).lowercased() == "location" {
                return p[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// 读设备描述 XML：friendlyName 与 AVTransport 的 controlURL（相对 URLBase 或 LOCATION）
    static func describe(_ location: String, fetch: HTTP.Fetch) async throws -> Renderer {
        let xml = HTTP.string(try await fetch(try HTTP.get(location, timeout: 3)))
        return try parse(xml, location: location)
    }

    static func parse(_ xml: String, location: String) throws -> Renderer {
        let name = tag(xml, "friendlyName") ?? location
        // 找到 AVTransport 所在的 <service> 块
        var control: String?
        for block in xml.components(separatedBy: "<service>").dropFirst() where block.contains("AVTransport") {
            control = tag(block, "controlURL")
            break
        }
        guard let control else { throw Failure.noTransport }
        let base = tag(xml, "URLBase") ?? location
        return Renderer(name: name, location: location, control: ConfigDecoder.resolve(base, control))
    }

    private static func tag(_ xml: String, _ name: String) -> String? {
        guard let s = xml.range(of: "<\(name)>"), let e = xml.range(of: "</\(name)>", range: s.upperBound..<xml.endIndex) else { return nil }
        let v = xml[s.upperBound..<e.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    // MARK: - 控制

    static func cast(_ url: String, title: String, to r: Renderer, fetch: @escaping HTTP.Fetch = HTTP.live) async throws {
        let meta = didl(url, title: title)
        try await soap(r, "SetAVTransportURI", "<CurrentURI>\(escape(url))</CurrentURI><CurrentURIMetaData>\(escape(meta))</CurrentURIMetaData>", fetch: fetch)
        try await soap(r, "Play", "<Speed>1</Speed>", fetch: fetch)
    }

    static func stop(_ r: Renderer, fetch: @escaping HTTP.Fetch = HTTP.live) async throws {
        try await soap(r, "Stop", "", fetch: fetch)
    }

    static func envelope(_ action: String, _ args: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>\
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\
        <s:Body><u:\(action) xmlns:u="\(avTransport)"><InstanceID>0</InstanceID>\(args)</u:\(action)></s:Body></s:Envelope>
        """
    }

    private static func soap(_ r: Renderer, _ action: String, _ args: String, fetch: HTTP.Fetch) async throws {
        guard let u = URL(string: r.control) else { throw Failure.noTransport }
        var req = URLRequest(url: u, timeoutInterval: 5)
        req.httpMethod = "POST"
        req.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        req.setValue("\"\(avTransport)#\(action)\"", forHTTPHeaderField: "SOAPAction")
        req.httpBody = Data(envelope(action, args).utf8)
        do {
            _ = try await fetch(req)
        } catch {
            throw Failure.soap((error as? URLError)?.errorCode ?? -1, action)
        }
    }

    private static func didl(_ url: String, title: String) -> String {
        """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"><item id="0" parentID="-1" restricted="1">\
        <dc:title>\(escape(title))</dc:title><upnp:class>object.item.videoItem</upnp:class>\
        <res protocolInfo="http-get:*:video/*:*">\(escape(url))</res></item></DIDL-Lite>
        """
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
