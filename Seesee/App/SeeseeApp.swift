import SwiftUI

@main
struct SeeseeApp: App {
    @State private var state = AppState()
    @Environment(\.scenePhase) private var phase

    init() {
        ServerRoutes.install()
        LocalServer.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
        }
        // iOS 挂起后监听会失效，回到前台重新拉起（端口通常不变）
        .onChange(of: phase) { if phase == .active { LocalServer.shared.restartIfNeeded() } }
    }
}
