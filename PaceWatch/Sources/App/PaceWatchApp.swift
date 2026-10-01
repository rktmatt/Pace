import SwiftUI

@main
struct PaceWatchApp: App {
    @StateObject private var sync = WatchSyncStore.shared

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(sync)
                .tint(WatchTheme.accent(sync.palette))
                .onAppear { sync.activate() }
        }
    }
}
