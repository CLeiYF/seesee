import SwiftUI
import UniformTypeIdentifiers

struct ConfigView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var importing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("配置地址", text: $url, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("加载") { load(url) }.disabled(url.isEmpty || state.loading)
                    Button("从文件导入") { importing = true }
                } footer: {
                    if let e = state.error { Text(e).foregroundStyle(.red) }
                }
                if !state.depots.isEmpty {
                    Section("仓库") {
                        ForEach(state.depots, id: \.url) { d in
                            Button(d.name.isEmpty ? d.url : d.name) { load(d.url) }
                        }
                    }
                }
                if !state.config.sites.isEmpty {
                    Section("首页站点") {
                        ForEach(state.config.homeSites) { site in
                            Button {
                                state.setHome(site)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(site.name).foregroundStyle(site.isSupported ? Color.primary : .secondary)
                                    Spacer()
                                    if !site.isSupported { Text("不支持").font(.caption).foregroundStyle(.secondary) }
                                    else if site.key == state.home?.key { Image(systemName: "checkmark") }
                                }
                            }
                            .disabled(!site.isSupported)
                        }
                    }
                }
                if !state.library.data.configs.isEmpty {
                    Section("历史") {
                        ForEach(state.library.data.configs) { c in
                            Button(c.url) { load(c.url) }.lineLimit(1)
                        }
                        .onDelete { $0.map { state.library.data.configs[$0].url }.forEach(state.library.removeConfig) }
                    }
                }
            }
            .navigationTitle("配置")
            .toolbar { Button("完成") { dismiss() } }
            .overlay { if state.loading { ProgressView() } }
            .onAppear { url = state.configURL }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, .data]) { result in
                guard case .success(let file) = result else { return }
                let ok = file.startAccessingSecurityScopedResource()
                defer { if ok { file.stopAccessingSecurityScopedResource() } }
                guard let raw = try? String(contentsOf: file, encoding: .utf8) else { return }
                Task { await state.load(file.absoluteString, raw: raw) }
            }
        }
    }

    private func load(_ u: String) {
        url = u
        Task {
            await state.load(u)
            if state.error == nil { dismiss() }
        }
    }
}
