import SwiftUI

/// App shell: Today (start the next session), Free run (self-paced, off-plan), Plan (the whole program and how
/// it has adapted), History (past runs with route recaps).
struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Today", systemImage: "figure.run") }
            FreeRunView()
                .tabItem { Label("Free run", systemImage: "stopwatch") }
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .tint(Theme.accent)
    }
}
