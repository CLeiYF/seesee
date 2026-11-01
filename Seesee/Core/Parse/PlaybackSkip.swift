import Foundation

/// 跳过片头片尾（秒），按影片记忆，对应 History.opening/ending
struct PlaybackSkip: Codable, Hashable {
    var opening: Double = 0
    var ending: Double = 0

    /// 起播位置：续播进度与片头取较大值
    func start(resume: Double) -> Double { max(opening, resume) }

    /// 进入片尾区间时结束本集
    func shouldEnd(position: Double, duration: Double) -> Bool {
        ending > 0 && duration > 0 && position + ending >= duration
    }
}
