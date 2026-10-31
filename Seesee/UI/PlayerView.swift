import AVKit
import SwiftUI

struct PlayerView: View {
    let api: SiteAPI
    let site: Site
    let flags: [Flag]
    let flag: Int
    let episode: Int
    let vipFlags: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var engine = PlayerEngine()

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: engine.player).ignoresSafeArea()
            HStack {
                Button("关闭", systemImage: "xmark") {
                    engine.stop()
                    dismiss()
                }
                .labelStyle(.iconOnly)
                Text(engine.title).lineLimit(1)
                Spacer()
                if engine.hasNext {
                    Button("下一集", systemImage: "forward.end.fill") { engine.next() }.labelStyle(.iconOnly)
                }
            }
            .padding()
            .foregroundStyle(.white)
            if !engine.status.isEmpty {
                Text(engine.status)
                    .font(.footnote).foregroundStyle(.white)
                    .padding(8).background(.black.opacity(0.6)).clipShape(Capsule())
                    .frame(maxHeight: .infinity)
            }
        }
        .onAppear {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            engine.start(api: api, site: site, flags: flags, flag: flag, episode: episode, vipFlags: vipFlags)
        }
        .onDisappear { engine.stop() }
    }
}
