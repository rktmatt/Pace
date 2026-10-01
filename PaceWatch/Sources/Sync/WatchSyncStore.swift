import Foundation
import WatchConnectivity

/// The Watch end of the iPhone link. Holds the latest plan the phone sent and
/// delivers finished runs back to it. The phone owns the plan: the Watch only
/// remembers which sessions it has run until the phone's next schedule
/// reflects them.
///
/// A run stays in the on-disk outbox until the phone confirms it has recorded
/// it — by replying to a direct message, or by listing its id in the schedule.
/// The system saying a transfer "finished" only means it left the Watch, which
/// isn't proof the phone app ever saw it, so it never clears the outbox.
@MainActor
final class WatchSyncStore: NSObject, ObservableObject {
    static let shared = WatchSyncStore()

    @Published private(set) var schedule: WatchSchedule?
    /// Sessions run on this Watch that the phone may not have recorded yet.
    @Published private(set) var completedSessionIDs: Set<UUID>
    /// Runs saved here that the phone hasn't confirmed recording yet.
    @Published private(set) var pendingRunCount = 0

    private static let completedKey = "completedSessionIDs"
    private let outbox: URL = {
        let directory = URL.applicationSupportDirectory.appending(path: "OutgoingRuns", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()
    /// Runs with a direct message in flight, so a flush doesn't send them twice.
    private var sending: Set<UUID> = []

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
        refreshPendingCount()
        guard WCSession.isSupported(), WCSession.default.delegate == nil else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Saves the run to the outbox, then tries to deliver it.
    func send(_ run: WatchRun) {
        if let sessionID = run.plannedSessionID {
            completedSessionIDs.insert(sessionID)
            saveCompleted()
        }
        guard let data = try? WatchSync.encoder.encode(run) else { return }
        try? data.write(to: fileURL(for: run.id), options: .atomic)
        refreshPendingCount()
        flushOutbox()
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

    // MARK: - Delivery

    /// Sends every unconfirmed run: as a direct message when the phone app is
    /// reachable (it replies once recorded), and as a queued file transfer
    /// otherwise, which the system delivers whenever the phone app next runs.
    /// Either way the phone records each run once, by id.
    func flushOutbox() {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated else { return }
        let inFlight = Set(session.outstandingFileTransfers.map { $0.file.fileURL.lastPathComponent })
        for url in outboxFiles() {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
            if session.isReachable {
                sendDirectly(id: id, url: url)
            } else if !inFlight.contains(url.lastPathComponent) {
                session.transferFile(url, metadata: [WatchSync.runMetadataKey: id.uuidString])
            }
        }
    }

    private func sendDirectly(id: UUID, url: URL) {
        guard !sending.contains(id), let data = try? Data(contentsOf: url) else { return }
        sending.insert(id)
        WCSession.default.sendMessageData(data, replyHandler: { reply in
            let acknowledged = (try? WatchSync.decoder.decode(WatchRunReceipt.self, from: reply))?.runID
            Task { @MainActor in
                self.sending.remove(id)
                if acknowledged == id { self.confirm([id]) }
            }
        }, errorHandler: { _ in
            // Unreachable mid-send, or over the message size limit (a long
            // route): queue it as a file, which has no size limit.
            Task { @MainActor in
                self.sending.remove(id)
                WCSession.default.transferFile(url, metadata: [WatchSync.runMetadataKey: id.uuidString])
            }
        })
    }

    /// The phone has recorded these runs: they can leave the outbox.
    private func confirm(_ ids: [UUID]) {
        for id in ids {
            try? FileManager.default.removeItem(at: fileURL(for: id))
        }
        refreshPendingCount()
    }

    private func fileURL(for id: UUID) -> URL {
        outbox.appending(path: "\(id.uuidString).json")
    }

    private func outboxFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" } ?? []
    }

    private func refreshPendingCount() {
        pendingRunCount = outboxFiles().count
    }

    // MARK: - Schedule

    private func apply(contextData data: Data?) {
        guard let data, let schedule = try? WatchSync.decoder.decode(WatchSchedule.self, from: data) else { return }
        confirm(schedule.recordedRunIDs ?? [])
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
        Task { @MainActor in
            self.requestSchedule()
            self.flushOutbox()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext[WatchSync.scheduleKey] as? Data
        Task { @MainActor in self.apply(contextData: data) }
    }
}
