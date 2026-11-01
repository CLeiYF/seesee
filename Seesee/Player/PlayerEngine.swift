import Foundation
import KSPlayer
import Observation

/// 选集 → 取地址（需要时走解析）→ KSPlayerLayer 播放。
/// KSPlayer 先用 AVPlayer，失败自动换 FFmpeg 内核（FLV/MKV/RTMP）；两者都失败或超时再换下一条线路。
@MainActor
@Observable
final class PlayerEngine {
    var flags: [Flag] = []
    var flagIndex = 0
    var episodeIndex = 0
    var status = ""
    var failed = false
    var position: Double = 0
    var duration: Double = 0
    var isPlaying = false
    var rate: Float = 1
    var subs: [Sub] = []
    var skip = PlaybackSkip()
    /// 定时关闭的截止时间
    var sleepAt: Date?

    @ObservationIgnored let coordinator = KSVideoPlayer.Coordinator()
    @ObservationIgnored private(set) var url: URL?
    @ObservationIgnored private(set) var options = KSOptions()

    @ObservationIgnored private var api: SiteAPI?
    @ObservationIgnored private var site = Site()
    @ObservationIgnored private var vipFlags: [String] = []
    @ObservationIgnored private var parses: [Parse] = []
    @ObservationIgnored private var parse: Parse?
    @ObservationIgnored private var fetch: HTTP.Fetch = HTTP.live
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var sleeper: Task<Void, Never>?
    @ObservationIgnored private var tried = Set<Int>()
    @ObservationIgnored private var resume: Double = 0
    @ObservationIgnored private var pendingSeek: Double = 0
    @ObservationIgnored private var lastReport: Double = 0
    /// (线路, 集名, 进度秒, 时长秒)
    @ObservationIgnored var onProgress: (String, String, Double, Double) -> Void = { _, _, _, _ in }
    /// 播放地址变化时通知视图重建播放器
    @ObservationIgnored var onURL: (URL, KSOptions) -> Void = { _, _ in }

    var title: String {
        guard flags.indices.contains(flagIndex), flags[flagIndex].episodes.indices.contains(episodeIndex) else { return "" }
        return flags[flagIndex].episodes[episodeIndex].name
    }

    var hasNext: Bool {
        flags.indices.contains(flagIndex) && episodeIndex + 1 < flags[flagIndex].episodes.count
    }

    func start(api: SiteAPI, site: Site, flags: [Flag], flag: Int, episode: Int, vipFlags: [String],
               parses: [Parse] = [], parse: Parse? = nil, fetch: @escaping HTTP.Fetch = HTTP.live, resume: Double = 0) {
        self.api = api
        self.site = site
        self.flags = flags
        self.vipFlags = vipFlags
        self.parses = parses
        self.parse = parse
        self.fetch = fetch
        self.resume = resume
        tried = []
        coordinator.onPlay = { [weak self] current, total in self?.tick(current, total) }
        coordinator.onStateChanged = { [weak self] _, state in self?.changed(state) }
        coordinator.onFinish = { [weak self] _, error in self?.finished(error) }
        play(flag: flag, episode: episode)
    }

    func play(flag: Int, episode: Int) {
        guard flags.indices.contains(flag), flags[flag].episodes.indices.contains(episode) else { return }
        flagIndex = flag
        episodeIndex = episode
        tried.insert(flag)
        failed = false
        status = "解析中…"
        let f = flags[flag]
        let ep = f.episodes[episode]
        Task {
            do {
                guard let api else { return }
                let r = try await api.player(flag: f.flag, id: ep.url, vipFlags: vipFlags)
                guard flagIndex == flag, episodeIndex == episode else { return }
                try await open(r, flag: f.flag)
            } catch {
                guard flagIndex == flag, episodeIndex == episode else { return }
                fail(error.localizedDescription)
            }
        }
    }

    func next() {
        guard hasNext else { return }
        report(force: true)
        resume = 0
        play(flag: flagIndex, episode: episodeIndex + 1)
    }

    func toggle() {
        guard let layer = coordinator.playerLayer else { return }
        if layer.player.isPlaying { layer.pause() } else { layer.play() }
    }

    func seek(_ time: Double) { coordinator.seek(time: time) }

    func setRate(_ r: Float) {
        rate = r
        coordinator.playbackRate = r
    }

    /// 定时关闭：minutes 为 0 取消
    func sleep(minutes: Int) {
        sleeper?.cancel()
        guard minutes > 0 else { sleepAt = nil; return }
        sleepAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleeper = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            self?.coordinator.playerLayer?.pause()
            self?.sleepAt = nil
        }
    }

    func stop() {
        report(force: true)
        watchdog?.cancel()
        sleeper?.cancel()
        coordinator.resetPlayer()
    }

    // MARK: -

    private func open(_ r: VodResult, flag: String) async throws {
        if !r.msg.isEmpty, r.url.isEmpty { throw ParseJob.Failure.message(r.msg) }
        var link = r.url.v
        var headers = site.header.merging(r.header) { $1 }
        // parse=1 / jx=1 需要解析（对应 Players.start → startParse）
        if r.parse == 1 || r.jx == 1 {
            status = "解析中…"
            let useParse = !parses.isEmpty && ((r.playUrl.isEmpty && vipFlags.contains(r.flag.isEmpty ? flag : r.flag)) || r.jx == 1)
            let p = ParseJob.pick(result: r, useParse: useParse, selected: parse ?? parses.first, parses: parses)
            let out = try await ParseJob.run(p, url: link, flag: flag, parses: parses, fetch: fetch)
            link = out.url
            headers = out.headers.isEmpty ? headers : out.headers
        }
        guard !link.isEmpty, let url = URL(string: link) ?? URL(string: link.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else {
            throw PlayError.emptyURL
        }
        let o = KSOptions()
        if !headers.isEmpty { o.appendHeader(headers) }
        if let ua = headers.first(where: { $0.key.lowercased() == "user-agent" })?.value { o.userAgent = ua }
        if let ref = headers.first(where: { $0.key.lowercased() == "referer" })?.value { o.referer = ref }
        // KSAVPlayer 忽略 startPlayTime，统一在 readyToPlay 时 seek
        pendingSeek = skip.start(resume: resume)
        resume = 0
        options = o
        self.url = url
        subs = r.subs
        status = "缓冲中…"
        onURL(url, o)
        startWatchdog()
    }

    /// 站点 changeable=0 时不自动换线（对应 isChangeable() ? timeout : -1）
    private func startWatchdog() {
        watchdog?.cancel()
        guard site.changeable == 1 else { return }
        let timeout = site.timeout
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.fail("播放超时")
        }
    }

    private func changed(_ state: KSPlayerState) {
        isPlaying = state.isPlaying
        switch state {
        case .readyToPlay, .bufferFinished:
            watchdog?.cancel()
            status = ""
            if rate != 1 { coordinator.playbackRate = rate }
            if pendingSeek > 1 {
                coordinator.seek(time: pendingSeek)
                pendingSeek = 0
            }
        case .error:
            fail("播放失败")
        default: break
        }
    }

    private func finished(_ error: Error?) {
        // KSPlayerLayer 已先在两种内核间重试；这里的 error 是最终失败
        if let error { fail(error.localizedDescription) } else { next() }
    }

    private func tick(_ current: Double, _ total: Double) {
        guard current.isFinite, total.isFinite else { return }
        position = current
        duration = total
        if skip.shouldEnd(position: current, duration: total), hasNext {
            next()
            return
        }
        report(force: false)
    }

    private func report(force: Bool) {
        guard flags.indices.contains(flagIndex), position > 0, force || abs(position - lastReport) >= 5 else { return }
        lastReport = position
        onProgress(flags[flagIndex].flag, title, position, duration)
    }

    /// 换下一条还没试过、且有这一集的线路
    private func fail(_ message: String) {
        watchdog?.cancel()
        let candidates = flags.indices.filter { !tried.contains($0) && flags[$0].episodes.indices.contains(episodeIndex) }
        if let next = candidates.first(where: { $0 > flagIndex }) ?? candidates.first {
            status = "\(message)，切换到 \(flags[next].flag)"
            play(flag: next, episode: episodeIndex)
        } else {
            status = message
            failed = true
        }
    }
}

enum PlayError: LocalizedError {
    case emptyURL

    var errorDescription: String? { "没有可播放的地址" }
}
