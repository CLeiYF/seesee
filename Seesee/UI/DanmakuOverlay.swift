import SwiftUI

/// 弹幕层：按播放时间取出弹幕分配到轨道，滚动弹幕从右向左，顶部/底部弹幕居中停留。
/// 播放器进度回调间隔较大，这里用 (time, at) 在两次回调之间按真实时间插值，保证滚动平滑。
/// ponytail: 轨道按"上一条离开起点"简单避让，不做逐像素碰撞；弹幕量极大时可能重叠
struct DanmakuOverlay: View {
    let items: [DanmakuItem]
    /// 最近一次播放进度及其对应的时刻
    let time: Double
    let at: Date
    let playing: Bool
    var duration: Double = 8
    var stay: Double = 4

    private let lineHeight: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: !playing)) { ctx in
                let now = time + (playing ? max(0, ctx.date.timeIntervalSince(at)) : 0)
                ZStack {
                    ForEach(Array(layout(now: now, size: geo.size).enumerated()), id: \.offset) { _, p in
                        Text(p.item.text)
                            .font(.system(size: max(12, min(p.item.size * 0.7, 30)), weight: .medium))
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

    private struct Placed { let item: DanmakuItem; let x: CGFloat; let y: CGFloat }

    private func layout(now: Double, size: CGSize) -> [Placed] {
        // 滚动弹幕用上半屏，顶部/底部各用 1/4
        let lanes = max(Int(size.height * 0.5 / lineHeight), 1)
        let fixedLanes = max(lanes / 2, 1)
        var scrollFree = [Double](repeating: -.infinity, count: lanes)
        var topFree = [Double](repeating: -.infinity, count: fixedLanes)
        var bottomFree = [Double](repeating: -.infinity, count: fixedLanes)
        var out: [Placed] = []
        for d in DanmakuParser.window(items, from: now - duration, to: now) {
            let age = now - d.time
            let width = CGFloat(d.text.count) * 16
            switch d.kind {
            case .scroll:
                guard let lane = scrollFree.firstIndex(where: { $0 <= d.time }) else { continue }
                // 本条尾部离开右边缘后，同轨道才放下一条
                scrollFree[lane] = d.time + duration * Double(width / (size.width + width)) + 0.3
                let x = size.width + width / 2 - CGFloat(age / duration) * (size.width + width)
                out.append(Placed(item: d, x: x, y: lineHeight * (CGFloat(lane) + 0.5)))
            case .top:
                guard age <= stay, let lane = topFree.firstIndex(where: { $0 <= d.time }) else { continue }
                topFree[lane] = d.time + stay
                out.append(Placed(item: d, x: size.width / 2, y: lineHeight * (CGFloat(lane) + 0.5)))
            case .bottom:
                guard age <= stay, let lane = bottomFree.firstIndex(where: { $0 <= d.time }) else { continue }
                bottomFree[lane] = d.time + stay
                out.append(Placed(item: d, x: size.width / 2, y: size.height - lineHeight * (CGFloat(lane) + 1.5)))
            }
        }
        return out
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
