import SwiftUI

/// 分类列表：筛选 + 无限滚动分页
struct CategoryView: View {
    let site: Site
    let cls: VodClass
    let filters: [Filter]
    @Environment(AppState.self) private var state
    @State private var items: [Vod] = []
    @State private var page = 1
    @State private var pagecount: Int?
    @State private var loading = false
    @State private var error: String?
    @State private var extend: [String: String] = [:]
    @State private var showFilter = false

    var body: some View {
        ScrollView {
            if showFilter { filterBar }
            VodGrid(items: items, style: cls.style ?? site.style ?? Style(), siteKey: site.key) {
                Task { await next() }
            }
            .padding(.vertical)
            if loading { ProgressView().padding() }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary).padding() }
        }
        .toolbar {
            if !filters.isEmpty {
                Button("筛选", systemImage: "line.3.horizontal.decrease.circle") { showFilter.toggle() }
            }
        }
        .task {
            extend = Dictionary(filters.compactMap { f in f.initial.map { (f.key, $0) } }, uniquingKeysWith: { a, _ in a })
            await reload()
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(filters, id: \.key) { f in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(f.value, id: \.self) { v in
                            let on = (extend[f.key] ?? "") == v.v
                            Button(v.n) {
                                extend[f.key] = v.v
                                Task { await reload() }
                            }
                            .font(.subheadline)
                            .foregroundStyle(on ? Color.accentColor : .secondary)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.top, 8)
    }

    private func reload() async {
        items = []
        page = 1
        pagecount = nil
        await fetch()
    }

    private func next() async {
        guard !loading, error == nil, pagecount.map({ page < $0 }) ?? true else { return }
        page += 1
        await fetch()
    }

    private func fetch() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let r = try await state.api(site).category(tid: cls.typeId, page: page, filter: true, extend: extend.filter { !$0.value.isEmpty })
            let fresh = r.list.filter { v in !items.contains { $0.id == v.id } }
            items += fresh
            // 没有 pagecount 时，空页即视为到底
            pagecount = r.pagecount ?? (fresh.isEmpty ? page : nil)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
