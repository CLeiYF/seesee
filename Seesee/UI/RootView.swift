import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var context
    @State private var showConfig = false

    var body: some View {
        NavigationStack {
            Group {
                if let home = state.home {
                    HomeView(site: home).id(home.key)
                } else if state.loading {
                    ProgressView("加载配置…")
                } else {
                    ContentUnavailableView {
                        Label("没有可用站点", systemImage: "tv")
                    } description: {
                        Text(state.error ?? "先添加一个配置地址")
                    } actions: {
                        Button("设置配置") { showConfig = true }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("配置", systemImage: "gearshape") { showConfig = true }
                }
            }
            .navigationDestination(for: VodRoute.self) { DetailView(route: $0) }
        }
        .sheet(isPresented: $showConfig) { ConfigView() }
        .task { await state.restore(context) }
        .alert(state.notice ?? "", isPresented: Binding(get: { state.notice != nil }, set: { if !$0 { state.notice = nil } })) {}
    }
}

/// 详情页导航参数
struct VodRoute: Hashable {
    let siteKey: String
    let vodId: String
    let name: String
    let pic: String
}
