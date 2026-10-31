import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        TabView {
            stack { HomeTab() }.tabItem { Label("首页", systemImage: "house") }
            stack { SearchView() }.tabItem { Label("搜索", systemImage: "magnifyingglass") }
            stack { MineView() }.tabItem { Label("我的", systemImage: "person") }
        }
        .task { await state.restore() }
        .alert(state.notice ?? "", isPresented: Binding(get: { state.notice != nil }, set: { if !$0 { state.notice = nil } })) {}
    }

    private func stack(@ViewBuilder _ content: () -> some View) -> some View {
        NavigationStack {
            content().navigationDestination(for: VodRoute.self) { DetailView(route: $0) }
        }
    }
}

struct HomeTab: View {
    @Environment(AppState.self) private var state
    @State private var showConfig = false

    var body: some View {
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
        .sheet(isPresented: $showConfig) { ConfigView() }
    }
}

/// 详情页导航参数
struct VodRoute: Hashable {
    let siteKey: String
    let vodId: String
    let name: String
    let pic: String
}
