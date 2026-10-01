import Foundation
import WatchConnectivity

/// The Watch end of the iPhone link. Holds the latest plan the phone sent and
/// queues finished runs back to it. The phone owns the plan: the Watch only
/// remembers which sessions it has run until the phone's next schedule
/// reflects them.
@MainActor
final class WatchSyncStore: NSObject, ObservableObject {
    static let shared = WatchSyncStore()

    @Published private(set) var schedule: WatchSchedule?
    /// Sessions run on this Watch that the phone may not have recorded yet.
    @Published private(set) var completedSessionIDs: Set<UUID>
    /// Runs written to disk and handed to the system, not yet confirmed delivered.
    @Published private(set) var pendingRunCount = 0

    private static let completedKey = "completedSessionIDs"
    private let outbox: URL = {
        let directory = URL.applicationSupportDirectory.appending(path: "OutgoingRuns", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    override init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.completedKey) ?? []
        completedSessionIDs = Set(stored.compactMap(UUID.init(uuidString:)))
        super.init()
    }

    var palette: String { schedule?.palette ?? "mint" }

    /// Planned sessions still to do, soonest first.
    var upcoming: [WatchSession] {
        (schedule?.sessions ?? []).filter { !completedSessionIDs.contains($0.id) }
    }

    func activate() {
        guard WCSession.isSupported(), WCSession.default.delegate == nil else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Saves the run to the outbox, then hands it to the system, which delivers
    /// it whenever the phone is reachable — now, or after both have restarted.
    func send(_ run: WatchRun) {
        if let sessionID = run.plannedSessionID {
            completedSessionIDs.insert(sessionID)
            saveCompleted()
        }
        guard let data = try? WatchSync.encoder.encode(run) else { return }
        let url = outbox.appending(path: "\(run.id.uuidString).json")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
        transfer(url)
        refreshPendingCount()
    }

    private func transfer(_ url: URL) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        session.transferFile(url, metadata: [WatchSync.runMetadataKey: url.deletingPathExtension().lastPathComponent])
    }

    /// Re-queues outbox files the system isn't already transferring — after a
    /// failed transfer, or a run saved before the session was active.
    private func flushOutbox() {
        let inFlight = Set(WCSession.default.outstandingFileTransfers.map { $0.file.fileURL.lastPathComponent })
        for url in outboxFiles() where !inFlight.contains(url.lastPathComponent) {
            transfer(url)
        }
        refreshPendingCount()
    }

    private func outboxFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil)) ?? []
    }

    private func refreshPendingCount() {
        pendingRunCount = outboxFiles().count
    }

    /// Asks the phone for the plan when it's reachable (both apps running).
    /// Otherwise the application context brings it once the phone app runs.
    func requestSchedule() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([WatchSync.requestScheduleKey: true], replyHandler: { reply in
            let data = reply[WatchSync.scheduleKey] as? Data
            Task { @MainActor in self.apply(contextData: data) }
        }, errorHandler: nil)
    }

    private func apply(contextData data: Data?) {
        guard let data, let schedule = try? WatchSync.decoder.decode(WatchSchedule.self, from: data) else { return }
        // Context and replies can arrive out of order: keep the newest.
        if let current = self.schedule, current.generatedAt > schedule.generatedAt { return }
        self.schedule = schedule
        // A session the phone no longer lists as planned has been recorded
        // there; only those still listed need remembering here.
        completedSessionIDs.formIntersection(schedule.sessions.map(\.id))
        saveCompleted()
    }

    private func saveCompleted() {
        UserDefaults.standard.set(completedSessionIDs.map(\.uuidString), forKey: Self.completedKey)
    }

    private func delivered(fileNamed name: String) {
        try? FileManager.default.removeItem(at: outbox.appending(path: name))
        refreshPendingCount()
    }
}

extension WatchSyncStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext[WatchSync.scheduleKey] as? Data
        Task { @MainActor in
            self.apply(contextData: data)
            self.flushOutbox()
            self.requestSchedule()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.requestSchedule() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext[WatchSync.scheduleKey] as? Data
        Task { @MainActor in self.apply(contextData: data) }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let name = fileTransfer.file.fileURL.lastPathComponent
        Task { @MainActor in
            if error == nil {
                self.delivered(fileNamed: name)
            } else {
                self.refreshPendingCount()
            }
        }
    }
}
