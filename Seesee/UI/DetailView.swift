import SwiftUI

struct DetailView: View {
    let route: VodRoute
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
        .task { await load() }
        .fullScreenCover(item: $playing) { t in
            if let site {
                PlayerView(api: state.api(site), site: site, flags: t.flags, flag: t.flag, episode: t.episode, vipFlags: state.config.flags)
            }
        }
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
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
