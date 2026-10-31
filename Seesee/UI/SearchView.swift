import SwiftUI

/// 聚合搜索：结果按站点分组，左侧（顶部）选站点过滤
struct SearchView: View {
    @Environment(AppState.self) private var state
    @State private var text = ""
    @State private var hits: [SearchHit] = []
    @State private var running = false
    @State private var filter: String?
    @State private var task: Task<Void, Never>?

    private var items: [Vod] {
        hits.filter { filter == nil || $0.site.key == filter }.flatMap(\.result.list)
    }

    var body: some View {
        ScrollView {
            if hits.isEmpty && !running {
                words
            } else {
                siteBar
                VodGrid(items: items, style: Style(type: "list"), siteKey: "").padding(.vertical)
                if running { ProgressView().padding() }
                if !running && hits.isEmpty { Text("没有结果").foregroundStyle(.secondary).padding() }
            }
        }
        .navigationTitle("搜索")
        .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "片名")
        .onSubmit(of: .search) { search(text) }
        .onChange(of: text) { if text.isEmpty { cancel(); hits = [] } }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !state.library.data.words.isEmpty {
                HStack {
                    Text("搜索历史").font(.headline)
                    Spacer()
                    Button("清空") { state.library.clearWords() }.font(.caption)
                }
                FlowLayout(spacing: 8) {
                    ForEach(state.library.data.words, id: \.self) { w in
                        Button(w) {
                            text = w
                            search(w)
                        }
                        .buttonStyle(.bordered)
                        .font(.subheadline)
                    }
                }
            }
            Text("将搜索 \(state.searchSites.count) 个站点").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var siteBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, "全部 \(hits.reduce(0) { $0 + $1.result.list.count })")
                ForEach(hits, id: \.site.key) { chip($0.site.key, "\($0.site.name) \($0.result.list.count)") }
            }
            .padding(.horizontal)
        }
        .padding(.top, 8)
    }

    private func chip(_ key: String?, _ title: String) -> some View {
        Button(title) { filter = key }
            .buttonStyle(.bordered)
            .tint(filter == key ? .accentColor : .secondary)
            .font(.caption)
    }

    private func search(_ keyword: String) {
        let keyword = keyword.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return }
        cancel()
        state.library.addWord(keyword)
        hits = []
        filter = nil
        running = true
        let api: @Sendable (Site) -> SiteAPI = { [fetch = state.fetch] site in makeAPI(site, fetch: fetch) }
        let stream = SearchRunner.run(keyword, sites: state.searchSites, quick: false, api: api)
        task = Task {
            for await hit in stream { hits.append(hit) }
            running = false
        }
    }

    private func cancel() {
        task?.cancel()
        running = false
    }
}

/// 自动换行排列
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in arrange(bounds.width, subviews).points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], width: CGFloat, height: CGFloat) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += row + spacing
                row = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            maxX = max(maxX, x)
            row = max(row, size.height)
        }
        return (points, maxX, y + row)
    }
}
