import KSPlayer
import SwiftUI

struct PlayerView: View {
    let api: SiteAPI
    let site: Site
    let flags: [Flag]
    let flag: Int
    let episode: Int
    let vipFlags: [String]
    var parses: [Parse] = []
    var resume: Double = 0
    var skip = PlaybackSkip()
    var vodName = ""
    /// (线路, 集名, 进度秒, 时长秒)
    var onProgress: (String, String, Double, Double) -> Void = { _, _, _, _ in }
    /// 用户修改片头片尾后回写
    var onSkip: (PlaybackSkip) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var engine = PlayerEngine()
    @State private var source: Source?
    @State private var controls = true
    @State private var casting = false

    private struct Source {
        let url: URL
        let options: KSOptions
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let source {
                // 不用 .id() 重建：重建时旧视图的 dismantleUIView 会晚于新视图调用 resetPlayer，把新播放器清掉
                KSVideoPlayer(coordinator: engine.coordinator, url: source.url, options: source.options)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { controls.toggle() } }
            }
            if engine.showDanmaku, !engine.danmaku.isEmpty {
                // 留在安全区内，避开灵动岛/刘海
                DanmakuOverlay(items: engine.danmaku, time: engine.position, at: engine.positionAt, playing: engine.isPlaying)
            }
            SubtitleOverlay(model: engine.coordinator.subtitleModel)
                .allowsHitTesting(false)
            if controls { overlay }
            if !engine.status.isEmpty {
                Text(engine.status)
                    .font(.footnote).foregroundStyle(.white)
                    .padding(8).background(.black.opacity(0.6)).clipShape(Capsule())
            }
        }
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
        .onAppear {
            engine.onProgress = onProgress
            engine.onURL = { url, options in
                // 地址相同（相同直链的另一集、重试）时 KSPlayer 视为同一媒体不会重新加载，回到起点即可
                if source?.url == url { engine.restartSameURL() }
                source = Source(url: url, options: options)
            }
            engine.skip = skip
            engine.vodName = vodName
            engine.start(api: api, site: site, flags: flags, flag: flag, episode: episode, vipFlags: vipFlags,
                         parses: parses, parse: parses.first, resume: resume)
        }
        .onDisappear { engine.stop() }
        .sheet(isPresented: $casting) {
            if let source { CastView(url: source.url, title: engine.title, headers: engine.headers) }
        }
        .onChange(of: engine.subs) { addSubs() }
    }

    private var overlay: some View {
        VStack {
            HStack(spacing: 16) {
                Button("关闭", systemImage: "xmark") {
                    engine.stop()
                    dismiss()
                }
                Text(engine.title).lineLimit(1)
                Spacer()
                if source != nil { Button("投屏", systemImage: "tv.and.mediabox") { casting = true } }
                menu
                if engine.hasNext { Button("下一集", systemImage: "forward.end.fill") { engine.next() } }
            }
            .labelStyle(.iconOnly)
            Spacer()
            HStack(spacing: 12) {
                Button(engine.isPlaying ? "暂停" : "播放", systemImage: engine.isPlaying ? "pause.fill" : "play.fill") { engine.toggle() }
                    .labelStyle(.iconOnly)
                Text(time(engine.position)).monospacedDigit()
                Slider(value: Binding(get: { engine.position }, set: { engine.seek($0) }), in: 0...max(engine.duration, 1))
                    .accessibilityLabel("播放进度")
                Text(time(engine.duration)).monospacedDigit()
            }
            .font(.caption)
        }
        .padding()
        .foregroundStyle(.white)
        .background(LinearGradient(colors: [.black.opacity(0.6), .clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
    }

    private var menu: some View {
        Menu {
            Menu("倍速 \(String(format: "%g", engine.rate))x") {
                ForEach([0.5, 0.75, 1, 1.25, 1.5, 2, 3] as [Float], id: \.self) { r in
                    Button("\(String(format: "%g", r))x") { engine.setRate(r) }
                }
            }
            Menu("线路") {
                ForEach(engine.flags.indices, id: \.self) { i in
                    Button(engine.flags[i].flag) { engine.play(flag: i, episode: engine.episodeIndex) }
                        .disabled(!engine.flags[i].episodes.indices.contains(engine.episodeIndex))
                }
            }
            let subtitles = engine.coordinator.subtitleModel.subtitleInfos
            if !subtitles.isEmpty {
                Menu("字幕") {
                    Button("关闭") { engine.coordinator.subtitleModel.selectedSubtitleInfo = nil }
                    ForEach(subtitles, id: \.subtitleID) { info in
                        Button(info.name) { engine.coordinator.subtitleModel.selectedSubtitleInfo = info }
                    }
                }
            }
            if !engine.danmakuSources.isEmpty {
                Menu("弹幕") {
                    Button(engine.showDanmaku ? "隐藏弹幕" : "显示弹幕") { engine.showDanmaku.toggle() }
                    if engine.danmakuSources.count > 1 {
                        ForEach(engine.danmakuSources, id: \.url) { src in Button(src.name) { engine.loadDanmaku(src) } }
                    }
                }
            }
            Menu("跳过片头片尾") {
                Button("片头设为当前（\(time(engine.position))）") { setSkip(opening: engine.position) }
                Button("片尾设为当前（剩 \(time(max(engine.duration - engine.position, 0)))）") {
                    setSkip(ending: max(engine.duration - engine.position, 0))
                }
                Button("清除") { setSkip(opening: 0, ending: 0) }
            }
            Menu(engine.sleepAt.map { "定时关闭（\($0.formatted(date: .omitted, time: .shortened))）" } ?? "定时关闭") {
                ForEach([0, 15, 30, 60, 90], id: \.self) { m in
                    Button(m == 0 ? "关闭" : "\(m) 分钟") { engine.sleep(minutes: m) }
                }
            }
        } label: {
            Label("更多", systemImage: "ellipsis.circle")
        }
    }

    private func setSkip(opening: Double? = nil, ending: Double? = nil) {
        if let opening { engine.skip.opening = opening }
        if let ending { engine.skip.ending = ending }
        onSkip(engine.skip)
    }

    /// 结果里的 subs 作为外挂字幕
    private func addSubs() {
        let urls = engine.subs.compactMap { URL(string: $0.url) }
        guard !urls.isEmpty else { return }
        engine.coordinator.subtitleModel.addSubtitle(dataSouce: URLSubtitleDataSouce(urls: urls))
    }

    private func time(_ t: Double) -> String {
        guard t.isFinite, t > 0 else { return "00:00" }
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// 外挂/内嵌字幕显示（KSPlayer 的 VideoSubtitleView 非 public）
private struct SubtitleOverlay: View {
    @ObservedObject var model: SubtitleModel

    var body: some View {
        VStack {
            Spacer()
            ForEach(model.parts) { part in
                if let image = part.image {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 120)
                } else if let text = part.text {
                    Text(AttributedString(text))
                        .font(.title3).foregroundStyle(.white).multilineTextAlignment(.center)
                        .shadow(color: .black, radius: 2)
                }
            }
        }
        .padding(.bottom, 48)
        .padding(.horizontal)
    }
}
