import SwiftUI
import SwiftData

@main
struct PaceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    private let modelContainer: ModelContainer = {
        let schema = Schema([ActiveProgram.self, PlannedSession.self, Run.self, RoutePoint.self, AdaptationRecord.self])
        let configuration = ModelConfiguration("Pace", schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .dark
    @AppStorage(Palette.storageKey) private var palette: Palette = .mint

    var body: some Scene {
        WindowGroup {
            RootView()
                .onAppear {
                    appearance.apply()
                    palette.apply()
                    PhoneWatchSync.shared.activate(container: modelContainer)
                }
                .onChange(of: appearance) { _, newValue in newValue.apply() }
                .onChange(of: palette) { _, newValue in
                    newValue.apply()
                    newValue.applyIcon()
                    PhoneWatchSync.shared.pushSchedule()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                QuickAction.updateShortcutItems(context: modelContainer.mainContext)
            }
            if phase != .inactive {
                PhoneWatchSync.shared.pushSchedule()
            }
        }
        .modelContainer(modelContainer)
    }
}
