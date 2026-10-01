import SwiftUI
import SwiftData

@main
struct PaceApp: App {
    private let modelContainer: ModelContainer = {
        let schema = Schema([ActiveProgram.self, PlannedSession.self, Run.self, RoutePoint.self, AdaptationRecord.self])
        let configuration = ModelConfiguration("Pace", schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .dark

    var body: some Scene {
        WindowGroup {
            RootView()
                .onAppear { appearance.apply() }
                .onChange(of: appearance) { _, newValue in newValue.apply() }
        }
        .modelContainer(modelContainer)
    }
}
