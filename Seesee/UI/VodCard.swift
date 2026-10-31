import SwiftUI

/// 按 style 渲染影片：rect/oval 网格卡片，list 横排
struct VodCard: View {
    let vod: Vod
    let style: Style

    var body: some View {
        if style.type == "list" {
            HStack(spacing: 12) {
                Poster(url: vod.vodPic).frame(width: 60, height: 80).clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 4) {
                    Text(vod.vodName).font(.body).lineLimit(1)
                    if !vod.vodRemarks.isEmpty { Text(vod.vodRemarks).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        } else {
            VStack(spacing: 4) {
                Poster(url: vod.vodPic)
                    .aspectRatio(style.effectiveRatio, contentMode: .fit)
                    .clipShape(style.type == "oval" ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8)))
                    .overlay(alignment: .bottomTrailing) {
                        if !vod.vodRemarks.isEmpty, style.type != "oval" {
                            Text(vod.vodRemarks).font(.caption2).lineLimit(1)
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(.black.opacity(0.6)).foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 4)).padding(4)
                        }
                    }
                Text(vod.vodName).font(.caption).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

struct Poster: View {
    let url: String

    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary).overlay { Image(systemName: "film").foregroundStyle(.secondary) }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

/// 影片网格/列表，滚到底触发 onEnd 加载下一页
struct VodGrid: View {
    let items: [Vod]
    let style: Style
    let siteKey: String
    var onEnd: (() -> Void)?

    private var columns: [GridItem] {
        let min: CGFloat = style.type == "list" ? 300 : (style.effectiveRatio > 1 ? 160 : 105)
        return [GridItem(.adaptive(minimum: min), spacing: 12)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(items) { vod in
                NavigationLink(value: VodRoute(siteKey: vod.siteKey.isEmpty ? siteKey : vod.siteKey, vodId: vod.vodId, name: vod.vodName, pic: vod.vodPic)) {
                    VodCard(vod: vod, style: vod.style ?? style)
                }
                .buttonStyle(.plain)
                .onAppear { if vod.id == items.last?.id { onEnd?() } }
            }
        }
        .padding(.horizontal)
    }
}
