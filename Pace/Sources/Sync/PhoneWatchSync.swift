import Foundation
import SwiftData
import WatchConnectivity

/// The iPhone end of the Watch link: keeps the Watch's copy of the plan current
/// and records the runs it sends back. Everything goes device to device.
@MainActor
final class PhoneWatchSync: NSObject {
    static let shared = PhoneWatchSync()

    private var container: ModelContainer?
    /// The last schedule handed to the system, so unchanged plans aren't resent.
    private var lastSent: WatchSchedule?

    func activate(container: ModelContainer) {
        self.container = container
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Sends the next planned sessions as the application context. Call after
    /// anything that may change the plan; it's a no-op when nothing did.
    func pushSchedule() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired,
              var schedule = currentSchedule(), schedule != lastSent else { return }
        let unstamped = schedule
        schedule.generatedAt = .now
        guard let data = try? WatchSync.encoder.encode(schedule) else { return }
        do {
            try session.updateApplicationContext([WatchSync.scheduleKey: data])
            lastSent = unstamped
        } catch {
            // Watch app not installed yet, or the session is mid-switch:
            // `sessionWatchStateDidChange` and the next push retry.
        }
    }

    /// The plan as the Watch needs it, stamped `.distantPast` so two
    /// snapshots compare equal when nothing changed.
    private func currentSchedule() -> WatchSchedule? {
        guard let context = container?.mainContext else { return nil }
        var descriptor = FetchDescriptor<PlannedSession>(sortBy: [SortDescriptor(\.scheduledAt)])
        descriptor.predicate = #Predicate { $0.stateRaw == "planned" }
        descriptor.fetchLimit = WatchSync.upcomingSessionLimit
        let sessions = (try? context.fetch(descriptor)) ?? []

        let definition = Couch5KProgram.definition
        return WatchSchedule(
            generatedAt: .distantPast,
            programTitle: definition.title,
            totalWeeks: definition.totalWeeks,
            sessions: sessions.map { session in
                WatchSession(id: session.id, week: session.week, scheduledAt: session.scheduledAt, kind: session.kind, title: session.title, intervals: session.intervals, adjustmentNote: session.adjustmentNote)
            },
            palette: UserDefaults.standard.string(forKey: Palette.storageKey) ?? Palette.mint.rawValue
        )
    }

    /// Direct answer to the Watch asking on launch — doesn't wait for the
    /// context to be redelivered.
    fileprivate func scheduleReply() -> [String: Any] {
        guard var schedule = currentSchedule() else { return [:] }
        schedule.generatedAt = .now
        guard let data = try? WatchSync.encoder.encode(schedule) else { return [:] }
        return [WatchSync.scheduleKey: data]
    }

    private func record(_ run: WatchRun) {
        guard let context = container?.mainContext else { return }
        guard ProgramCoordinator(context: context).recordWatchRun(run) != nil else { return }
        try? context.save()
        pushSchedule()
    }
}

extension PhoneWatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.pushSchedule() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.lastSent = nil
            self.pushSchedule()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Switching to another Watch: reactivate so the new one gets the plan.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard message[WatchSync.requestScheduleKey] != nil else { return replyHandler([:]) }
        Task { @MainActor in replyHandler(self.scheduleReply()) }
    }

    /// The file is deleted when this returns, so it's read here, synchronously.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?[WatchSync.runMetadataKey] != nil,
              let data = try? Data(contentsOf: file.fileURL),
              let run = try? WatchSync.decoder.decode(WatchRun.self, from: data) else { return }
        Task { @MainActor in self.record(run) }
    }
}
