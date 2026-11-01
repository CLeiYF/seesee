import SwiftUI

/// 投屏：同时扫描 DLNA 渲染器与局域网里的 FongMi 影视，选中后推送当前播放地址
struct CastView: View {
    let url: URL
    let title: String
    let headers: [String: String]
    @Environment(\.dismiss) private var dismiss
    @State private var devices: [DLNA.Renderer] = []
    @State private var apps: [DevicePush.Device] = []
    @State private var scanning = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                if !headers.isEmpty {
                    Section { Text("该地址需要请求头，部分电视端可能无法播放").font(.footnote).foregroundStyle(.secondary) }
                }
                if !apps.isEmpty {
                    Section("影视") {
                        ForEach(apps) { d in
                            Button { push(d) } label: { Label("\(d.name)（\(d.kind)）", systemImage: "play.tv") }
                        }
                    }
                }
                Section("DLNA") {
                    ForEach(devices) { d in
                        Button { cast(d) } label: { Label(d.name, systemImage: "tv") }
                    }
                }
                Section {
                    EmptyView()
                } footer: {
                    if scanning { ProgressView() } else if devices.isEmpty && apps.isEmpty { Text("没有找到设备。确认电视与手机在同一 Wi-Fi，并已允许本地网络权限") }
                }
            }
            .navigationTitle("投屏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("刷新", systemImage: "arrow.clockwise") { Task { await scan() } }.disabled(scanning) }
            }
            .task { await scan() }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {}
        }
    }

    private func scan() async {
        scanning = true
        async let d = DLNA.discover()
        async let a = DevicePush.scan()
        (devices, apps) = await (d, a)
        scanning = false
    }

    private func push(_ d: DevicePush.Device) {
        Task {
            do {
                try await DevicePush.push(url.absoluteString, to: d)
                dismiss()
            } catch {
                message = "\(d.name) 未响应"
            }
        }
    }

    private func cast(_ d: DLNA.Renderer) {
        Task {
            do {
                try await DLNA.cast(url.absoluteString, title: title, to: d)
                dismiss()
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
