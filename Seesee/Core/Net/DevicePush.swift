import Darwin
import Foundation

/// 推送到局域网里的 FongMi 影视（TV/手机端）：扫描同网段 :9978/device，再调用 /action?do=push&url=…
/// 对应原项目 ScanTask + CastDialog 的设备互推部分。
/// ponytail: 只做发送端；接收端需要把本地服务绑到局域网 IP（会把 /proxy、/cache 暴露给同网段），且 iOS 后台无法常驻，暂不做
enum DevicePush {
    struct Device: Decodable, Hashable, Identifiable {
        var name = ""
        var ip = ""
        var type = 0
        var id: String { ip }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            name = c.str(AnyKey("name"))
            ip = c.str(AnyKey("ip"))
            type = c.int(AnyKey("type")) ?? 0
        }

        var kind: String { type == 0 ? "电视" : type == 1 ? "手机" : "设备" }
    }

    /// 本机 Wi-Fi（en0）IPv4
    static func localIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = p.pointee
            guard i.ifa_addr.pointee.sa_family == UInt8(AF_INET), String(cString: i.ifa_name) == "en0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(i.ifa_addr, socklen_t(i.ifa_addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            return String(cString: host)
        }
        return nil
    }

    /// 同网段 1…254 并发探测，最多 32 路，单个 1 秒超时
    static func scan(subnetOf ip: String? = localIP(), fetch: @escaping HTTP.Fetch = HTTP.live) async -> [Device] {
        guard let ip, let dot = ip.lastIndex(of: ".") else { return [] }
        let base = ip[...dot]
        let hosts = (1...254).map { "\(base)\($0)" }.filter { $0 != ip }
        return await withTaskGroup(of: Device?.self) { g in
            var next = 0
            func add() {
                guard next < hosts.count else { return }
                let h = hosts[next]
                next += 1
                g.addTask { try? await probe("http://\(h):9978", fetch: fetch) }
            }
            for _ in 0..<32 { add() }
            var out: [Device] = []
            for await d in g {
                if let d { out.append(d) }
                add()
            }
            return out.sorted { $0.ip < $1.ip }
        }
    }

    static func probe(_ base: String, fetch: HTTP.Fetch) async throws -> Device {
        let data = try await fetch(try HTTP.get(base + "/device", timeout: 1))
        var d = try JSONDecoder().decode(Device.self, from: data)
        if d.ip.isEmpty { d.ip = base }
        return d
    }

    /// 推送播放地址；对方返回 OK 视为成功
    static func push(_ url: String, to d: Device, fetch: HTTP.Fetch = HTTP.live) async throws {
        let req = try HTTP.get(d.ip + "/action", query: [("do", "push"), ("url", url)], timeout: 5)
        guard HTTP.string(try await fetch(req)).trimmingCharacters(in: .whitespacesAndNewlines) == "OK" else {
            throw URLError(.badServerResponse)
        }
    }
}
