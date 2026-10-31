import AVFoundation
import Observation

/// 选集 → 取播放地址 → AVPlayer；超时或失败时切到下一条线路的同一集
@MainActor
@Observable
final class PlayerEngine {
    let player = AVPlayer()
    var flags: [Flag] = []
    var flagIndex = 0
    var episodeIndex = 0
    var status = ""
    var failed = false

    @ObservationIgnored private var api: SiteAPI?
    @ObservationIgnored private var site = Site()
    @ObservationIgnored private var vipFlags: [String] = []
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var observer: NSKeyValueObservation?
    @ObservationIgnored private var tried = Set<Int>()
    @ObservationIgnored private var resume: Double = 0
    @ObservationIgnored private var ticker: Any?
    /// (线路, 集名, 进度秒, 时长秒)，约每 5 秒及停止时回调
    @ObservationIgnored var onProgress: (String, String, Double, Double) -> Void = { _, _, _, _ in }

    var title: String {
        guard flags.indices.contains(flagIndex), flags[flagIndex].episodes.indices.contains(episodeIndex) else { return "" }
        return flags[flagIndex].episodes[episodeIndex].name
    }

    func start(api: SiteAPI, site: Site, flags: [Flag], flag: Int, episode: Int, vipFlags: [String], resume: Double = 0) {
        self.api = api
        self.site = site
        self.flags = flags
        self.vipFlags = vipFlags
        self.resume = resume
        tried = []
        ticker = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }
        play(flag: flag, episode: episode)
    }

    private func report() {
        guard let item = player.currentItem, flags.indices.contains(flagIndex) else { return }
        let position = item.currentTime().seconds
        let duration = item.duration.seconds
        guard position.isFinite, position > 0 else { return }
        onProgress(flags[flagIndex].flag, title, position, duration.isFinite ? duration : 0)
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
                try open(r)
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    func next() {
        guard flags.indices.contains(flagIndex) else { return }
        report()
        resume = 0
        play(flag: flagIndex, episode: episodeIndex + 1)
    }

    var hasNext: Bool {
        flags.indices.contains(flagIndex) && episodeIndex + 1 < flags[flagIndex].episodes.count
    }

    func stop() {
        report()
        watchdog?.cancel()
        observer = nil
        if let ticker { player.removeTimeObserver(ticker) }
        ticker = nil
        player.replaceCurrentItem(with: nil)
    }

    private func open(_ r: VodResult) throws {
        // parse=1 或 jx=1 需要解析，M4 接入 ParseJob
        if r.parse == 1 || r.jx == 1 { throw PlayError.needParse }
        guard !r.url.isEmpty, let url = URL(string: r.url.v) else { throw PlayError.emptyURL }
        let headers = site.header.merging(r.header) { $1 }
        let asset = AVURLAsset(url: url, options: headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        observer = item.observe(\.status) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.watchdog?.cancel()
                    self.status = ""
                    // 续播：只用一次，快到结尾时不跳
                    let d = item.duration.seconds
                    if self.resume > 5, !d.isFinite || self.resume < d - 10 {
                        item.seek(to: CMTime(seconds: self.resume, preferredTimescale: 600), completionHandler: nil)
                    }
                    self.resume = 0
                case .failed:
                    self.fail(item.error?.localizedDescription ?? "播放失败")
                default: break
                }
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
        status = "缓冲中…"
        watchdog?.cancel()
        let timeout = site.timeout
        watchdog = Task {
            try? await Task.sleep(for: .seconds(timeout))
            if !Task.isCancelled { fail("播放超时") }
        }
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
    case needParse, emptyURL

    var errorDescription: String? {
        switch self {
        case .needParse: "该地址需要解析（M4 支持）"
        case .emptyURL: "没有可播放的地址"
        }
    }
}
