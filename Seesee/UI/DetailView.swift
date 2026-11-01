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
            if let vod {
                let kept = state.library.isKept(keepItem(vod).id)
                Button(kept ? "取消收藏" : "收藏", systemImage: kept ? "heart.fill" : "heart") {
                    state.library.toggleKeep(keepItem(vod))
                }
            }
        }
        .task { await load() }
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
                    info("导演", vod.vodDirector)
                    info("主演", vod.vodActor)
                    info("备注", vod.vodRemarks)
                }
                .font(.caption)
            }
            if !vod.vodContent.isEmpty {
                Text(vod.vodContent.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(6)
            }
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
