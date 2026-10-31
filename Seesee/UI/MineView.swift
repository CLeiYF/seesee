import SwiftUI
import UniformTypeIdentifiers

/// 我的：观看记录、收藏、搜索站点开关、备份
struct MineView: View {
    @Environment(AppState.self) private var state
    @State private var exporting = false
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                NavigationLink("观看记录") { HistoryView() }
                NavigationLink("收藏") { KeepView() }
            }
            Section("搜索站点") {
                NavigationLink("参与搜索的站点（\(state.searchSites.count)）") { SearchSitesView() }
            }
            Section("备份") {
                Button("导出备份") { exporting = true }
                Button("导入备份") { importing = true }
            }
        }
        .navigationTitle("我的")
        .fileExporter(isPresented: $exporting, document: BackupFile(data: (try? state.library.export()) ?? Data()),
                      contentType: .json, defaultFilename: "seesee-backup") { result in
            if case .failure(let e) = result { message = e.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let file) = result else { return }
            let ok = file.startAccessingSecurityScopedResource()
            defer { if ok { file.stopAccessingSecurityScopedResource() } }
            do {
                try state.library.restore(Data(contentsOf: file))
                message = "已恢复"
            } catch {
                message = "备份文件无效：\(error.localizedDescription)"
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {}
    }
}

struct BackupFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct HistoryView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let items = state.library.history(config: state.configURL)
        List {
            ForEach(items) { h in
                NavigationLink(value: VodRoute(siteKey: h.siteKey, vodId: h.vodId, name: h.vodName, pic: h.vodPic)) {
                    row(h.vodPic, h.vodName, [state.site(h.siteKey)?.name, h.episode, progress(h)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                }
            }
            .onDelete { $0.map { items[$0].id }.forEach(state.library.removeHistory) }
        }
        .overlay { if items.isEmpty { ContentUnavailableView("暂无观看记录", systemImage: "clock") } }
        .navigationTitle("观看记录")
        .toolbar {
            if !items.isEmpty { Button("清空") { state.library.clearHistory(config: state.configURL) } }
        }
    }

    private func progress(_ h: HistoryItem) -> String? {
        guard h.duration > 0 else { return nil }
        return "\(Int(h.position / h.duration * 100))%"
    }
}

struct KeepView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let items = state.library.keep(config: state.configURL)
        List {
            ForEach(items) { k in
                NavigationLink(value: VodRoute(siteKey: k.siteKey, vodId: k.vodId, name: k.vodName, pic: k.vodPic)) {
                    row(k.vodPic, k.vodName, state.site(k.siteKey)?.name ?? "")
                }
            }
            .onDelete { $0.map { items[$0] }.forEach(state.library.toggleKeep) }
        }
        .overlay { if items.isEmpty { ContentUnavailableView("暂无收藏", systemImage: "heart") } }
        .navigationTitle("收藏")
    }
}

struct SearchSitesView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        List(state.config.sites.filter { $0.isSupported && $0.searchable == 1 }) { site in
            Toggle(site.name, isOn: Binding(
                get: { state.library.isSearchable(site) },
                set: { state.library.setSearchable(site.key, $0) }))
        }
        .navigationTitle("搜索站点")
    }
}

private func row(_ pic: String, _ title: String, _ subtitle: String) -> some View {
    HStack(spacing: 12) {
        Poster(url: pic).frame(width: 50, height: 66).clipShape(RoundedRectangle(cornerRadius: 6))
        VStack(alignment: .leading, spacing: 4) {
            Text(title).lineLimit(1)
            if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
    }
}
