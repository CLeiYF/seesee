import AVFAudio
import KSPlayer
import MediaPlayer
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
    @State private var locked = false
    @State private var episodes = false
    /// 手势中的提示（拖动进度、亮度、倍速）
    @State private var hint: String?
    @State private var dragStart: (x: Double, value: Double, horizontal: Bool, left: Bool)?
    @State private var holdRate: Float?

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
            }
            // 隐藏的系统音量控件：右半屏竖拖改音量要用它的滑块，放在画面里也能顶掉系统音量 HUD
            SystemVolume().frame(width: 1, height: 1).opacity(0.01).allowsHitTesting(false)
            // 手势层：单击显隐、双击暂停、横向拖动快进、左半屏竖拖亮度、右半屏竖拖音量、长按 2 倍速
            GeometryReader { geo in
                Color.clear.contentShape(Rectangle())
                    .onTapGesture(count: 2) { if !locked { engine.toggle() } }
                    .onTapGesture { withAnimation { controls.toggle() } }
                    .gesture(locked ? nil : drag(geo.size))
                    .simultaneousGesture(locked ? nil : hold)
            }
            .ignoresSafeArea()
            if engine.showDanmaku, !engine.danmaku.isEmpty {
                // 留在安全区内，避开灵动岛/刘海
                DanmakuOverlay(items: engine.danmaku, time: engine.position, at: engine.positionAt, playing: engine.isPlaying)
            }
            SubtitleOverlay(model: engine.coordinator.subtitleModel)
                .allowsHitTesting(false)
            if controls {
                if locked { lockButton.frame(maxWidth: .infinity, alignment: .leading).padding() } else { overlay }
            }
            if let hint {
                Text(hint).font(.headline.monospacedDigit()).foregroundStyle(.white)
                    .padding(12).background(.black.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 8))
            }
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
        .sheet(isPresented: $episodes) { episodeSheet.presentationDetents([.medium, .large]) }
    }

    private var lockButton: some View {
        Button(locked ? "解锁" : "锁定", systemImage: locked ? "lock.fill" : "lock.open") { locked.toggle() }
            .labelStyle(.iconOnly).font(.title2).foregroundStyle(.white)
            .padding(10).background(.black.opacity(0.4)).clipShape(Circle())
    }

    private var episodeSheet: some View {
        NavigationStack {
            let eps = engine.flags.indices.contains(engine.flagIndex) ? engine.flags[engine.flagIndex].episodes : []
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                    ForEach(eps.indices, id: \.self) { i in
                        Button { engine.jump(i); episodes = false } label: {
                            Text(eps[i].name).lineLimit(1).frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered).tint(i == engine.episodeIndex ? .accentColor : .secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("选集").navigationBarTitleDisplayMode(.inline)
        }
    }

    /// 横向：拖动快进（满屏宽 = 3 分钟）；竖向左半屏：亮度，右半屏：音量
    private func drag(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { g in
                if dragStart == nil {
                    let horizontal = abs(g.translation.width) > abs(g.translation.height)
                    let left = g.startLocation.x < size.width / 2
                    let value = horizontal ? engine.position
                        : left ? Double(UIScreen.main.brightness) : Double(AVAudioSession.sharedInstance().outputVolume)
                    dragStart = (Double(g.startLocation.x), value, horizontal, left)
                }
                guard let d = dragStart else { return }
                if d.horizontal {
                    let t = min(max(d.value + Double(g.translation.width / size.width) * 180, 0), engine.duration)
                    hint = "\(time(t)) / \(time(engine.duration))"
                } else {
                    let b = min(max(d.value - Double(g.translation.height / size.height), 0), 1)
                    if d.left {
                        UIScreen.main.brightness = CGFloat(b)
                        hint = "亮度 \(Int(b * 100))%"
                    } else {
                        SystemVolume.set(Float(b))
                        hint = "音量 \(Int(b * 100))%"
                    }
                }
            }
            .onEnded { g in
                if let d = dragStart, d.horizontal == true {
                    engine.seek(min(max(d.value + Double(g.translation.width / size.width) * 180, 0), engine.duration))
                }
                dragStart = nil
                hint = nil
            }
    }

    /// 长按 2 倍速，松开恢复
    private var hold: some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { v in
                guard case .second = v, holdRate == nil else { return }
                holdRate = engine.rate
                engine.setRate(2)
                hint = "2x 快进中"
            }
            .onEnded { _ in
                if let r = holdRate { engine.setRate(r) }
                holdRate = nil
                hint = nil
            }
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
                if source != nil {
                    Button("画中画", systemImage: "pip.enter") { engine.togglePiP() }
                    Button("投屏", systemImage: "tv.and.mediabox") { casting = true }
                }
                menu
            }
            .labelStyle(.iconOnly)
            Spacer()
            HStack {
                lockButton
                Spacer()
                Button("旋转", systemImage: "rectangle.landscape.rotate") { rotate() }
                    .labelStyle(.iconOnly).font(.title3)
                    .padding(10).background(.black.opacity(0.4)).clipShape(Circle())
            }
            Spacer()
            HStack(spacing: 12) {
                if engine.hasPrev { Button("上一集", systemImage: "backward.end.fill") { engine.prev() }.labelStyle(.iconOnly) }
                Button(engine.isPlaying ? "暂停" : "播放", systemImage: engine.isPlaying ? "pause.fill" : "play.fill") { engine.toggle() }
                    .labelStyle(.iconOnly)
                if engine.hasNext { Button("下一集", systemImage: "forward.end.fill") { engine.next() }.labelStyle(.iconOnly) }
                Text(time(engine.position)).monospacedDigit()
                Slider(value: Binding(get: { engine.position }, set: { engine.seek($0) }), in: 0...max(engine.duration, 1))
                    .accessibilityLabel("播放进度")
                Text(time(engine.duration)).monospacedDigit()
                if engine.flags.indices.contains(engine.flagIndex), engine.flags[engine.flagIndex].episodes.count > 1 {
                    Button("选集") { episodes = true }
                }
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
            Menu("画面 \(engine.scale.rawValue)") {
                ForEach(PlayerEngine.Scale.allCases, id: \.self) { m in Button(m.rawValue) { engine.scale = m } }
            }
            Button(engine.loop ? "关闭单集循环" : "单集循环") { engine.loop.toggle() }
            let audios = engine.audioTracks()
            if audios.count > 1 {
                Menu("音轨") {
                    ForEach(audios.indices, id: \.self) { i in
                        Button((audios[i].isEnabled ? "✓ " : "") + audios[i].name) { engine.select(track: audios[i]) }
                    }
                }
            }
            if engine.parseList.count > 1 {
                Menu("解析 \(engine.parseName)") {
                    ForEach(engine.parseList, id: \.self) { p in Button(p.name) { engine.selectParse(p) } }
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

    /// 横竖屏切换（对应原项目的旋转按钮）
    private func rotate() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let landscape = scene.effectiveGeometry.interfaceOrientation.isLandscape
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: landscape ? .portrait : .landscapeRight))
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

/// 系统音量只能通过 MPVolumeView 里的滑块改（没有公开 API）；视图需在窗口里才生效
private struct SystemVolume: UIViewRepresentable {
    nonisolated(unsafe) private static weak var slider: UISlider?

    static func set(_ value: Float) { slider?.setValue(value, animated: false) }

    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: .zero)
        Self.slider = v.subviews.compactMap { $0 as? UISlider }.first
        return v
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
