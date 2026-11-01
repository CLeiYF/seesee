import SwiftUI

struct DetailView: View {
    let route: VodRoute
    /// 调试：加载后直接播放该线路第一集
    var autoplay: Int?
    @Environment(AppState.self) private var state
    @State private var vod: Vod?
    @State private var error: String?
    @State private var flagIndex = 0
    @State private var reversed = false
    @State private var playing: PlayTarget?
    @State private var expanded = false
    /// 换源：快搜其它站点的同名结果（对应 VideoActivity 的 quickSearch）
    @State private var sources: [Vod] = []
    @State private var searching = false

    private var site: Site? { state.site(route.siteKey) }

    var body: some View {
        ScrollView {
            if let vod {
                content(vod)
            } else if let error {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if vod != nil || error != nil {
                Button("刷新", systemImage: "arrow.clockwise") { Task { await reload() } }
            }
            if let vod {
                let kept = state.library.isKept(keepItem(vod).id)
                Button(kept ? "取消收藏" : "收藏", systemImage: kept ? "heart.fill" : "heart") {
                    state.library.toggleKeep(keepItem(vod))
                }
            }
        }
        .task { await load() }
        .refreshable { await reload() }
        .fullScreenCover(item: $playing) { t in
            if let site, let vod {
                PlayerView(api: state.api(site), site: site, flags: t.flags, flag: t.flag, episode: t.episode,
                           vipFlags: state.config.flags, parses: state.config.parses, resume: t.resume,
                           skip: history?.skip ?? PlaybackSkip(), vodName: vod.vodName,
                           onProgress: { flag, episode, position, duration in
                               record(vod) { $0.flag = flag; $0.episode = episode; $0.position = position; $0.duration = duration }
                           },
                           onSkip: { skip in record(vod) { $0.skip = skip } })
            }
        }
    }

    /// 更新观看记录（保留已有字段，如片头片尾）
    private func record(_ vod: Vod, _ change: (inout HistoryItem) -> Void) {
        guard !Prefs.incognito else { return }
        var h = history ?? HistoryItem(config: state.configURL, siteKey: route.siteKey, vodId: route.vodId)
        h.vodName = vod.vodName.isEmpty ? route.name : vod.vodName
        h.vodPic = vod.vodPic.isEmpty ? route.pic : vod.vodPic
        h.time = Date()
        change(&h)
        state.library.record(h)
    }

    private var history: HistoryItem? {
        state.library.history(config: state.configURL, siteKey: route.siteKey, vodId: route.vodId)
    }

    private func keepItem(_ vod: Vod) -> KeepItem {
        KeepItem(config: state.configURL, siteKey: route.siteKey, vodId: route.vodId,
                 vodName: vod.vodName.isEmpty ? route.name : vod.vodName, vodPic: vod.vodPic.isEmpty ? route.pic : vod.vodPic)
    }

    /// 从上次观看的线路与集数继续
    private func resume(_ flags: [Flag]) {
        guard let h = history,
              let f = flags.firstIndex(where: { $0.flag == h.flag }) ?? flags.indices.first,
              let e = flags[f].episodes.firstIndex(where: { $0.name == h.episode }) else { return }
        playing = PlayTarget(flags: flags, flag: f, episode: e, resume: h.position)
    }

    private func content(_ vod: Vod) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Poster(url: vod.vodPic.isEmpty ? route.pic : vod.vodPic)
                    .frame(width: 110, height: 150).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(vod.vodName.isEmpty ? route.name : vod.vodName).font(.headline)
                    info("站点", site?.name ?? "")
                    info("年份", vod.vodYear)
                    info("地区", vod.vodArea)
                    info("类型", vod.typeName)
                    people("导演", vod.vodDirector)
                    people("主演", vod.vodActor)
                    info("备注", vod.vodRemarks)
                }
                .font(.caption)
            }
            if !vod.vodContent.isEmpty {
                Text(vod.vodContent.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(expanded ? nil : 6)
                    .onTapGesture { withAnimation { expanded.toggle() } }
                    .accessibilityHint(expanded ? "收起简介" : "展开简介")
            }
            switchSource(vod)
            let flags = vod.flags
            if flags.isEmpty {
                Text("没有播放线路").foregroundStyle(.secondary)
            } else {
                if let h = history {
                    Button("继续观看 \(h.episode)", systemImage: "play.fill") { resume(flags) }
                        .buttonStyle(.borderedProminent)
                }
                Picker("线路", selection: $flagIndex) {
                    ForEach(flags.indices, id: \.self) { Text(flags[$0].flag).tag($0) }
                }
                .pickerStyle(.menu)
                HStack {
                    Text("选集 (\(flags[safe: flagIndex]?.episodes.count ?? 0))").font(.subheadline.bold())
                    Spacer()
                    Button(reversed ? "正序" : "倒序", systemImage: "arrow.up.arrow.down") { reversed.toggle() }.font(.caption)
                }
                episodes(flags)
            }
        }
        .padding()
    }

    private func episodes(_ flags: [Flag]) -> some View {
        let eps = Array((flags[safe: flagIndex]?.episodes ?? []).enumerated())
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
            ForEach(reversed ? eps.reversed() : eps, id: \.offset) { i, ep in
                Button { playing = PlayTarget(flags: flags, flag: flagIndex, episode: i) } label: {
                    Text(ep.name).font(.caption).lineLimit(1).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    /// 演员、导演：逐个可点，转全局搜索
    @ViewBuilder private func people(_ k: String, _ v: String) -> some View {
        let names = v.split(whereSeparator: { ",，/、 ".contains($0) }).map(String.init).filter { !$0.isEmpty }
        if !names.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(k)：")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(names.prefix(8), id: \.self) { n in
                            Button(n) { state.pendingSearch = n; state.tab = 2 }.foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    /// 换源：按片名在开启快搜的站点里搜，点结果打开该站详情
    @ViewBuilder private func switchSource(_ vod: Vod) -> some View {
        let name = vod.vodName.isEmpty ? route.name : vod.vodName
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("换源").font(.subheadline.bold())
                Spacer()
                if searching { ProgressView().controlSize(.small) }
                else { Button(sources.isEmpty ? "查找" : "重新查找") { quickSearch(name) }.font(.caption) }
            }
            if !sources.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sources) { v in
                            NavigationLink(value: VodRoute(siteKey: v.siteKey, vodId: v.vodId, name: v.vodName, pic: v.vodPic)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(state.site(v.siteKey)?.name ?? v.siteKey).font(.caption.bold())
                                    Text(v.vodRemarks.isEmpty ? v.vodName : v.vodRemarks).font(.caption2).foregroundStyle(.secondary)
                                }
                                .lineLimit(1).padding(8).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func quickSearch(_ name: String) {
        sources = []
        searching = true
        let sites = state.searchSites.filter { $0.key != route.siteKey }
        let api: @Sendable (Site) -> SiteAPI = { [fetch = state.fetch] in makeAPI($0, fetch: fetch) }
        Task {
            for await hit in SearchRunner.run(name, sites: sites, quick: true, api: api) {
                // 只要同名结果（对应原项目按名称匹配）
                sources += hit.result.list.filter { Self.sameTitle($0.vodName, name) }.prefix(3)
            }
            searching = false
        }
    }

    static func sameTitle(_ a: String, _ b: String) -> Bool {
        let n = { (s: String) in s.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation } }
        let x = n(a), y = n(b)
        return !x.isEmpty && (x == y || x.contains(y) || y.contains(x))
    }

    private func reload() async {
        vod = nil
        error = nil
        sources = []
        await load()
    }

    @ViewBuilder private func info(_ k: String, _ v: String) -> some View {
        if !v.isEmpty { Text("\(k)：\(v)").lineLimit(2) }
    }

    private func load() async {
        guard vod == nil, let site else {
            if site == nil { error = "站点不存在" }
            return
        }
        do {
            let r = try await state.api(site).detail(ids: [route.vodId])
            guard let v = r.list.first else { throw PlayError.emptyURL }
            vod = v
            if let h = history, let f = v.flags.firstIndex(where: { $0.flag == h.flag }) { flagIndex = f }
            if let f = autoplay, v.flags.indices.contains(f) { playing = PlayTarget(flags: v.flags, flag: f, episode: 0) }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PlayTarget: Identifiable {
    let id = UUID()
    let flags: [Flag]
    let flag: Int
    let episode: Int
    var resume: Double = 0
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
