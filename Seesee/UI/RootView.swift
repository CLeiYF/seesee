import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state
    #if DEBUG
    @State private var debugPlay: DebugPlay?
    struct DebugPlay: Identifiable { let id = UUID(); let route: VodRoute; let flag: Int }
    @State private var debugFolder: FolderRoute?
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
                let p = arg.split(separator: "/").map { $0.removingPercentEncoding ?? String($0) }
                if p.count == 3 { debugPlay = DebugPlay(route: VodRoute(siteKey: p[0], vodId: p[1], name: "", pic: ""), flag: Int(p[2]) ?? 0) }
            }
        }
        #endif
        #if DEBUG
        // 调试用 `-folder <siteKey>/<id>`：打开文件夹（simctl 无法点击）
        .sheet(item: $debugFolder) { f in NavigationStack { FolderView(route: f) } }
        .onChange(of: state.home?.key) {
            if let arg = UserDefaults.standard.string(forKey: "folder"), let i = arg.firstIndex(of: "/") {
                debugFolder = FolderRoute(siteKey: String(arg[..<i]), id: String(arg[arg.index(after: i)...]), name: "调试")
            }
        }
        #endif
        #if DEBUG
        // ponytail: 调试用 `-search <词>` 配置加载后直接搜索（simctl 无法输入）
        .onChange(of: state.home?.key) {
            if let w = UserDefaults.standard.string(forKey: "search"), state.pendingSearch == nil {
                UserDefaults.standard.removeObject(forKey: "search")
                state.pendingSearch = w
                state.tab = 2
            }
        }
        #endif
        .alert(state.notice ?? "", isPresented: Binding(get: { state.notice != nil }, set: { if !$0 { state.notice = nil } })) {}
    }

    private func stack(@ViewBuilder _ content: () -> some View) -> some View {
        NavigationStack {
            content()
                .navigationDestination(for: VodRoute.self) { DetailView(route: $0) }
                .navigationDestination(for: FolderRoute.self) { FolderView(route: $0) }
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

/// 文件夹导航参数（vod_tag=folder）
struct FolderRoute: Hashable, Identifiable {
    let siteKey: String
    let id: String
    let name: String
}

/// 文件夹：复用分类列表，tid 为文件夹 id
struct FolderView: View {
    let route: FolderRoute
    @Environment(AppState.self) private var state

    var body: some View {
        if let site = state.site(route.siteKey) {
            CategoryView(site: site, cls: VodClass(typeId: route.id, typeName: route.name), filters: [])
                .navigationTitle(route.name)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("站点不存在", systemImage: "folder")
        }
    }
}
