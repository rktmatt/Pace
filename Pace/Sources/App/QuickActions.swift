import SwiftUI
import SwiftData
import UIKit

/// Home Screen quick actions (long-press / Force Touch on the app icon).
///
/// All items are dynamic rather than declared in Info.plist: iOS lists static items
/// before dynamic ones, and "Start week N" (the next planned session) should come first.
/// They're rebuilt whenever the app goes to the background.
enum QuickAction: String {
    case startSession = "start-session"
    case freeRun = "free-run"
    case plan
    case history

    var type: String { "\(Bundle.main.bundleIdentifier ?? "Pace").\(rawValue)" }

    init?(shortcutItem: UIApplicationShortcutItem) {
        guard let raw = shortcutItem.type.split(separator: ".").last.map(String.init) else { return nil }
        self.init(rawValue: raw)
    }

    /// Rebuilds the menu: "Start week N" while a planned session remains, then the tabs.
    @MainActor
    static func updateShortcutItems(context: ModelContext) {
        var descriptor = FetchDescriptor<PlannedSession>(sortBy: [SortDescriptor(\.scheduledAt)])
        descriptor.predicate = #Predicate { $0.stateRaw == "planned" }
        descriptor.fetchLimit = 1

        var items: [UIApplicationShortcutItem] = []
        if let session = try? context.fetch(descriptor).first {
            items.append(item(.startSession, "Start week \(session.week)", subtitle: "\(session.plannedDurationSeconds / 60) min · \(session.title)", symbol: "figure.run"))
        }
        items.append(item(.freeRun, "Free run", symbol: "stopwatch"))
        items.append(item(.plan, "Plan", symbol: "calendar"))
        items.append(item(.history, "History", symbol: "clock.arrow.circlepath"))
        UIApplication.shared.shortcutItems = items
    }

    private static func item(_ action: QuickAction, _ title: String, subtitle: String? = nil, symbol: String) -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(type: action.type, localizedTitle: title, localizedSubtitle: subtitle, icon: UIApplicationShortcutIcon(systemImageName: symbol))
    }
}

/// Holds the quick action the user picked until the view that handles it consumes it.
@MainActor
final class QuickActionRouter: ObservableObject {
    static let shared = QuickActionRouter()

    @Published var pending: QuickAction?

    /// Set by `ActiveRunView` so a quick action never starts a second run on top of one in progress.
    var isRunInProgress = false

    func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard let action = QuickAction(shortcutItem: item) else { return false }
        if !isRunInProgress { pending = action }
        return true
    }
}

/// SwiftUI has no quick-action hook, so a scene delegate catches both cold launches
/// (`connectionOptions.shortcutItem`) and warm ones (`performActionFor`).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem {
            MainActor.assumeIsolated { _ = QuickActionRouter.shared.handle(item) }
        }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        let handled = MainActor.assumeIsolated { QuickActionRouter.shared.handle(shortcutItem) }
        completionHandler(handled)
    }
}
