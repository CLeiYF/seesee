import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state
    #if DEBUG
    @State private var debugPlay: DebugPlay?
    struct DebugPlay: Identifiable { let id = UUID(); let route: VodRoute; let flag: Int }
    #endif

    var body: some View {
        @Bindable var state = state
        TabView(selection: $state.tab) {
            stack { HomeTab() }.tabItem { Label("首页", systemImage: "house") }.tag(0)
            stack { LiveView() }.tabItem { Label("直播", systemImage: "antenna.radiowaves.left.and.right") }.tag(1)
            stack { SearchView() }.tabItem { Label("搜索", systemImage: "magnifyingglass") }.tag(2)
            stack { MineView() }.tabItem { Label("我的", systemImage: "person") }.tag(3)
        }
        .task { await state.restore() }
        #if DEBUG
        // ponytail: 调试用 `-play <siteKey>/<vodId>/<flag序号>` 直接打开播放器（simctl 无法点击）
        .fullScreenCover(item: $debugPlay) { r in DetailView(route: r.route, autoplay: r.flag) }
        .onChange(of: state.home?.key) {
            if debugPlay == nil, let arg = UserDefaults.standard.string(forKey: "play") {
                let p = arg.split(separator: "/").map(String.init)
                if p.count == 3 { debugPlay = DebugPlay(route: VodRoute(siteKey: p[0], vodId: p[1], name: "", pic: ""), flag: Int(p[2]) ?? 0) }
            }
        }
        #endif
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
