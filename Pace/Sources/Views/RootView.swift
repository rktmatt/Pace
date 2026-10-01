import SwiftUI

/// App shell: Today (start the next session), Free run (self-paced, off-plan), Plan (the whole program and how
/// it has adapted), History (past runs with route recaps).
struct RootView: View {
    enum Tab { case today, freeRun, plan, history }

    @StateObject private var quickActions = QuickActionRouter.shared
    @State private var tab: Tab = .today

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("Today", systemImage: "figure.run") }
                .tag(Tab.today)
            FreeRunView()
                .tabItem { Label("Free run", systemImage: "stopwatch") }
                .tag(Tab.freeRun)
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(Tab.plan)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)
        }
        .tint(Theme.accent)
        .onAppear { route(quickActions.pending) }
        .onChange(of: quickActions.pending) { _, action in route(action) }
    }

    /// Switches to the quick action's tab. Plan and History are done once there;
    /// Home and Free run consume the action themselves to start the run.
    private func route(_ action: QuickAction?) {
        switch action {
        case .startSession: tab = .today
        case .freeRun: tab = .freeRun
        case .plan: tab = .plan; quickActions.pending = nil
        case .history: tab = .history; quickActions.pending = nil
        case nil: break
        }
    }
}
