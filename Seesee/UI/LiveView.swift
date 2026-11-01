import KSPlayer
import SwiftUI

/// 直播：上方播放器，下方分组 / 频道 / 节目单
struct LiveView: View {
    @Environment(AppState.self) private var state
    @State private var liveIndex = 0
    @State private var live = Live()
    @State private var groups: [LiveGroup] = []
    @State private var groupIndex = 0
    @State private var unlocked: Set<String> = []
    @State private var askPass: LiveGroup?
    @State private var passInput = ""
    @State private var channel: Channel?
    @State private var line = 0
    @State private var xml: [String: [Programme]] = [:]
    @State private var epg: [Programme] = []
    @State private var playURL: PlayItem?
    @State private var error: String?
    @State private var loading = false

    struct PlayItem: Identifiable {
        let id = UUID()
        let url: URL
        let headers: [String: String]
        let title: String
    }

    private var visibleGroups: [LiveGroup] { groups.filter { $0.pass.isEmpty || unlocked.contains($0.name) } }
    private var locked: [LiveGroup] { groups.filter { !$0.pass.isEmpty && !unlocked.contains($0.name) } }

    var body: some View {
        VStack(spacing: 0) {
            player
            if state.config.lives.isEmpty {
                ContentUnavailableView("配置里没有直播源", systemImage: "antenna.radiowaves.left.and.right")
            } else if loading {
                ProgressView().frame(maxHeight: .infinity)
            } else if let error {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: { Button("重试") { Task { await load() } } }
            } else {
                lists
            }
        }
        .navigationTitle(live.name.isEmpty ? "直播" : live.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if state.config.lives.count > 1 {
                Menu("直播源", systemImage: "list.bullet") {
                    ForEach(state.config.lives.indices, id: \.self) { i in
                        Button(state.config.lives[i].name) { liveIndex = i; Task { await load() } }
                    }
                }
            }
            if !locked.isEmpty {
                Menu("解锁", systemImage: "lock") {
                    ForEach(locked) { g in Button(g.name) { askPass = g } }
                }
            }
        }
        .alert("输入密码", isPresented: Binding(get: { askPass != nil }, set: { if !$0 { askPass = nil } })) {
            SecureField("密码", text: $passInput)
            Button("确定") {
                if let g = askPass, passInput == g.pass { unlocked.insert(g.name) }
                passInput = ""
            }
            Button("取消", role: .cancel) { passInput = "" }
        }
        .task(id: state.configURL) { liveIndex = state.config.lives.firstIndex(where: \.boot) ?? 0; await load() }
    }

    @ViewBuilder private var player: some View {
        ZStack {
            Color.black
            if let p = playURL {
                LivePlayer(item: p, timeout: live.timeout) { nextLine() }.id(p.id)
            } else {
                Image(systemName: "tv").font(.largeTitle).foregroundStyle(.secondary)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
    }

    private var lists: some View {
        HStack(spacing: 0) {
            List(visibleGroups.indices, id: \.self, selection: Binding(get: { groupIndex }, set: { groupIndex = $0 ?? 0 })) { i in
                Text(visibleGroups[i].name).lineLimit(1).tag(i)
            }
            .listStyle(.plain)
            .frame(maxWidth: 110)
            Divider()
            List(visibleGroups[safe: groupIndex]?.channels ?? []) { c in
                Button { select(c) } label: {
                    HStack {
                        Text(c.number).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Text(c.name).lineLimit(1)
                        Spacer()
                        if c.urls.count > 1 { Text("\(c.urls.count) 线").font(.caption2).foregroundStyle(.secondary) }
                    }
                    .foregroundStyle(c == channel ? Color.accentColor : .primary)
                }
            }
            .listStyle(.plain)
            if channel != nil, !epg.isEmpty {
                Divider()
                programmeList.frame(maxWidth: 220)
            }
        }
    }

    private var programmeList: some View {
        ScrollViewReader { proxy in
            List(epg) { p in
                Button { replay(p) } label: {
                    VStack(alignment: .leading) {
                        Text(p.title).lineLimit(1)
                        Text("\(p.start.formatted(date: .omitted, time: .shortened)) - \(p.end.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(p.isLive() ? Color.accentColor : (p.isPast() && channel?.catchup != nil ? .primary : .secondary))
                }
                .disabled(!(p.isPast() && channel?.catchup != nil) && !p.isLive())
                .id(p.id)
            }
            .listStyle(.plain)
            .onAppear { if let now = epg.first(where: { $0.isLive() }) { proxy.scrollTo(now.id, anchor: .center) } }
        }
    }

    // MARK: -

    private func load() async {
        guard state.config.lives.indices.contains(liveIndex) else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let r = try await LiveLoader.groups(state.config.lives[liveIndex], fetch: state.fetch)
            live = r.live
            groups = r.groups
            groupIndex = 0
            unlocked = []
            if let first = visibleGroups.first?.channels.first { select(first) }
            xml = await LiveLoader.xmltv(live.epgXml, timeZone: live.zone, fetch: state.fetch)
            if let channel { await loadEPG(channel) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func select(_ c: Channel) {
        line = channel == c ? (line + 1) % max(c.urls.count, 1) : 0
        channel = c
        play(c.urls[safe: line] ?? "", title: c.name)
        Task { await loadEPG(c) }
    }

    private func nextLine() {
        guard let c = channel, c.urls.count > 1 else { return }
        line = (line + 1) % c.urls.count
        play(c.urls[line], title: "\(c.name) 线路\(line + 1)")
    }

    private func play(_ raw: String, title: String) {
        guard let c = channel else { return }
        let u = Channel.line(raw).url
        guard let url = URL(string: u) else { return }
        playURL = PlayItem(url: url, headers: c.headers, title: title)
    }

    private func replay(_ p: Programme) {
        guard let c = channel else { return }
        if p.isLive() { return play(c.urls[safe: line] ?? "", title: c.name) }
        guard let catchup = c.catchup else { return }
        let base = Channel.line(c.urls[safe: line] ?? "").url
        play(catchup.url(base, start: p.start, end: p.end, timeZone: live.zone), title: "\(c.name) 回看 \(p.title)")
    }

    private func loadEPG(_ c: Channel) async {
        let list = xml[c.tvgId] ?? xml[c.tvgName] ?? xml[c.name] ?? []
        let today = list.filter { Calendar.current.isDateInToday($0.start) }
        if !today.isEmpty { epg = today; return }
        epg = await LiveLoader.programmes(c, timeZone: live.zone, fetch: state.fetch)
    }
}

/// 直播播放器：KSPlayer（FFmpeg 兜底），超时或失败回调换线
private struct LivePlayer: View {
    let item: LiveView.PlayItem
    let timeout: Int
    let onFail: () -> Void
    private let options: KSOptions
    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
    @State private var watchdog: Task<Void, Never>?

    init(item: LiveView.PlayItem, timeout: Int, onFail: @escaping () -> Void) {
        self.item = item
        self.timeout = timeout
        self.onFail = onFail
        let o = KSOptions()
        if !item.headers.isEmpty { o.appendHeader(item.headers) }
        if let ua = item.headers["User-Agent"] { o.userAgent = ua }
        if let r = item.headers["Referer"] { o.referer = r }
        options = o
    }

    var body: some View {
        KSVideoPlayer(coordinator: coordinator, url: item.url, options: options)
            .onStateChanged { _, s in
                if s == .bufferFinished || s == .readyToPlay { watchdog?.cancel() }
                if s == .error { onFail() }
            }
            .onAppear {
                watchdog = Task {
                    try? await Task.sleep(for: .seconds(timeout))
                    if !Task.isCancelled { onFail() }
                }
            }
            .onDisappear { watchdog?.cancel() }
            .accessibilityLabel(item.title)
    }
}
