import SwiftUI

@main
struct PaceWatchApp: App {
    @StateObject private var sync = WatchSyncStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(sync)
                .tint(WatchTheme.accent(sync.palette))
                .onAppear { sync.activate() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                sync.requestSchedule()
                sync.flushOutbox()
            }
        }
    }
}
