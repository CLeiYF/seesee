import SwiftUI

/// 弹幕层：滚动弹幕固定速度从右向左（同轨道不会追尾），顶部/底部弹幕居中停留。
/// 轨道按时间顺序一次性分配并缓存，避免逐帧重算时旧弹幕移出导致后面的跳轨。
/// 播放器进度回调间隔较大，用 (time, at) 在两次回调之间按真实时间插值，保证滚动平滑。
struct DanmakuOverlay: View {
    let items: [DanmakuItem]
    /// 最近一次播放进度及其对应的时刻
    let time: Double
    let at: Date
    let playing: Bool
    /// 滚动弹幕横穿一屏所需秒数
    var crossing: Double = 8
    var stay: Double = 4

    private let lineHeight: CGFloat = 28
    @State private var cache = LaneCache()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: !playing)) { ctx in
                let now = time + (playing ? max(0, ctx.date.timeIntervalSince(at)) : 0)
                ZStack {
                    ForEach(placed(now: now, size: geo.size), id: \.index) { p in
                        Text(p.item.text)
                            .font(.system(size: Self.fontSize(p.item), weight: .medium))
                            .foregroundStyle(Color(hex: p.item.color))
                            .shadow(color: .black.opacity(0.8), radius: 1, x: 1, y: 1)
                            .lineLimit(1)
                            .fixedSize()
                            .position(x: p.x, y: p.y)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .clipped()
        .accessibilityHidden(true)
    }

    static func fontSize(_ d: DanmakuItem) -> CGFloat { max(14, min(d.size * 0.72, 30)) }

    /// 估算宽度：中日韩字符约 1em，其余约 0.6em
    static func width(_ d: DanmakuItem) -> CGFloat {
        let em = fontSize(d)
        return d.text.unicodeScalars.reduce(0) { $0 + ($1.value > 0x2E80 ? em : em * 0.6) } + 8
    }

    private struct Placed { let index: Int; let item: DanmakuItem; let x: CGFloat; let y: CGFloat }

    private func placed(now: Double, size: CGSize) -> [Placed] {
        let lanes = cache.lanes(items, size: size, lineHeight: lineHeight, crossing: crossing, stay: stay)
        let speed = size.width / crossing
        // 最长弹幕也已完全离开屏幕的时间跨度
        let span = max(crossing * 2, stay)
        var out: [Placed] = []
        let window = DanmakuParser.window(items, from: now - span, to: now)
        for i in window.indices {
            guard let lane = lanes[i] else { continue }
            let d = items[i]
            let age = now - d.time
            let w = Self.width(d)
            switch d.kind {
            case .scroll:
                let x = size.width + w / 2 - CGFloat(age) * speed
                guard x > -w / 2 else { continue }
                out.append(Placed(index: i, item: d, x: x, y: lineHeight * (CGFloat(lane) + 0.5)))
            case .top:
                guard age <= stay else { continue }
                out.append(Placed(index: i, item: d, x: size.width / 2, y: lineHeight * (CGFloat(lane) + 0.5)))
            case .bottom:
                guard age <= stay else { continue }
                out.append(Placed(index: i, item: d, x: size.width / 2, y: size.height - lineHeight * (CGFloat(lane) + 0.5)))
            }
        }
        return out
    }
}

/// 轨道分配结果缓存：弹幕列表或尺寸变化时才重算
final class LaneCache {
    private var key: (count: Int, first: Double, width: CGFloat, height: CGFloat)?
    private var result: [Int?] = []

    func lanes(_ items: [DanmakuItem], size: CGSize, lineHeight: CGFloat, crossing: Double, stay: Double) -> [Int?] {
        let k = (items.count, items.first?.time ?? 0, size.width, size.height)
        if let key, key == k { return result }
        key = k
        result = Self.assign(items, size: size, lineHeight: lineHeight, crossing: crossing, stay: stay)
        return result
    }

    /// 滚动弹幕占上半区；顶部/底部各占 1/4。放不下的丢弃（nil）
    static func assign(_ items: [DanmakuItem], size: CGSize, lineHeight: CGFloat, crossing: Double, stay: Double) -> [Int?] {
        let scrollLanes = max(Int(size.height * 0.5 / lineHeight), 1)
        let fixedLanes = max(Int(size.height * 0.25 / lineHeight), 1)
        let speed = max(size.width, 1) / crossing
        var scrollFree = [Double](repeating: -.infinity, count: scrollLanes)
        var topFree = [Double](repeating: -.infinity, count: fixedLanes)
        var bottomFree = [Double](repeating: -.infinity, count: fixedLanes)
        return items.map { d in
            switch d.kind {
            case .scroll:
                guard let lane = scrollFree.firstIndex(where: { $0 <= d.time }) else { return nil }
                // 固定速度下，前一条尾部进入屏幕后留 24pt 间隔，下一条即可出发且不会追上
                scrollFree[lane] = d.time + Double((DanmakuOverlay.width(d) + 24) / speed)
                return lane
            case .top:
                guard let lane = topFree.firstIndex(where: { $0 <= d.time }) else { return nil }
                topFree[lane] = d.time + stay
                return lane
            case .bottom:
                guard let lane = bottomFree.firstIndex(where: { $0 <= d.time }) else { return nil }
                bottomFree[lane] = d.time + stay
                return lane
            }
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
