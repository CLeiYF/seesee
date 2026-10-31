import SwiftUI

/// 首页：顶部分类 tab，第 0 项为"推荐"（home 返回的 list）
struct HomeView: View {
    let site: Site
    @Environment(AppState.self) private var state
    @State private var home: VodResult?
    @State private var error: String?
    @State private var selected = ""

    private let recommend = "__home__"

    var body: some View {
        VStack(spacing: 0) {
            if let home {
                tabs(home.classes)
                if selected == recommend {
                    ScrollView { VodGrid(items: home.list, style: site.style ?? Style(), siteKey: site.key).padding(.vertical) }
                } else if let cls = home.classes.first(where: { $0.typeId == selected }) {
                    CategoryView(site: site, cls: cls, filters: home.filters[cls.typeId] ?? []).id(cls.typeId)
                }
            } else if let error {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { Task { await load() } }
                }
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        .navigationTitle(site.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func tabs(_ classes: [VodClass]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                tab(recommend, "推荐")
                ForEach(classes) { tab($0.typeId, $0.typeName) }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func tab(_ id: String, _ name: String) -> some View {
        Button(name) { selected = id }
            .fontWeight(selected == id ? .bold : .regular)
            .foregroundStyle(selected == id ? Color.accentColor : .primary)
    }

    private func load() async {
        error = nil
        do {
            let r = try await state.api(site).home()
            home = r
            selected = r.list.isEmpty ? (r.classes.first?.typeId ?? recommend) : recommend
        } catch {
            self.error = error.localizedDescription
        }
    }
}
