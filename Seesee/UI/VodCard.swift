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
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary).overlay { Image(systemName: "film").foregroundStyle(.secondary) }
            }
        }
        .clipped()
        .accessibilityHidden(true)
        .task(id: url) {
            image = nil
            // ponytail: 依赖 URLCache 默认缓存，图多了卡再加内存缓存
            guard let req = Poster.request(url), let (data, _) = try? await URLSession.shared.data(for: req) else { return }
            image = UIImage(data: data)
        }
    }

    /// CatVod 图片写法 `url@Referer=xxx@User-Agent=yyy`：@ 之后是请求头
    static func request(_ raw: String) -> URLRequest? {
        // 只在 `@Name=` 处切分，避免误伤 `x@2x.png` 这类地址
        let parts = raw.split(separator: #/@(?=[A-Za-z][A-Za-z-]*=)/#).map(String.init)
        guard let first = parts.first, let u = URL(string: first), u.scheme != nil else { return nil }
        var req = URLRequest(url: u)
        for p in parts.dropFirst() {
            let kv = p.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { req.setValue(kv[1], forHTTPHeaderField: kv[0]) }
        }
        return req
    }
}

/// 影片网格/列表，滚到底触发 onEnd 加载下一页
struct VodGrid: View {
    @Environment(AppState.self) private var state
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
                Group {
                    if vod.vodId.hasPrefix("msearch:") {
                        // 豆瓣等推荐源：没有详情，点击转全局搜索（对应 FongMi 的 msearch）
                        Button { state.pendingSearch = vod.vodName; state.tab = 2 } label: { VodCard(vod: vod, style: vod.style ?? style) }
                    } else {
                        NavigationLink(value: VodRoute(siteKey: vod.siteKey.isEmpty ? siteKey : vod.siteKey, vodId: vod.vodId, name: vod.vodName, pic: vod.vodPic)) {
                            VodCard(vod: vod, style: vod.style ?? style)
                        }
                    }
                }
                .buttonStyle(.plain)
                .onAppear { if vod.id == items.last?.id { onEnd?() } }
            }
        }
        .padding(.horizontal)
    }
}
