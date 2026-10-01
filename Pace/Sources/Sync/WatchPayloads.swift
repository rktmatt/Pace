import Foundation

/// What crosses between the iPhone and the Watch over WatchConnectivity —
/// directly between the user's own devices, never through a server.
///
/// The phone stays the source of truth for the plan: it sends the upcoming
/// sessions down as the application context (only the latest one matters), and
/// the Watch sends each finished run up — as a direct message when the phone
/// app is reachable, otherwise as a file transfer the system queues — and keeps
/// it until the phone confirms it was recorded.
enum WatchSync {
    static let scheduleKey = "schedule"
    static let runMetadataKey = "run"
    /// Message the Watch sends on launch to ask for the plan when the phone is
    /// reachable; the reply carries the schedule under `scheduleKey`.
    static let requestScheduleKey = "requestSchedule"
    /// Recorded run ids echoed back to the Watch as delivery receipts.
    static let receiptLimit = 30
    /// Upcoming sessions sent to the Watch: enough for a week or two without
    /// the phone, small enough to stay well under the context size limit.
    static let upcomingSessionLimit = 6

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}

/// A planned session as the Watch needs it to run it.
struct WatchSession: Codable, Hashable, Identifiable {
    var id: UUID
    var week: Int
    var scheduledAt: Date
    var kind: SessionKind
    var title: String
    var intervals: [IntervalDefinition]
    var adjustmentNote: String?

    var plannedDurationSeconds: Int { intervals.reduce(0) { $0 + $1.durationSeconds * Swift.max($1.repeatCount, 1) } }
}

/// The plan as of `generatedAt`: the next planned sessions, soonest first.
struct WatchSchedule: Codable, Hashable {
    var generatedAt: Date
    var programTitle: String
    var totalWeeks: Int
    var sessions: [WatchSession]
    /// Mint or pink, so the Watch matches the phone.
    var palette: String
    /// The most recent runs the phone has recorded. The Watch keeps each run it
    /// sends until its id shows up here (or in a `WatchRunReceipt`).
    var recordedRunIDs: [UUID]?
}

/// The phone's reply to a run sent as a direct message: recorded (or already
/// had it), so the Watch can drop its copy.
struct WatchRunReceipt: Codable, Hashable {
    var runID: UUID
}

/// A run finished on the Watch, sent to the phone to be recorded.
struct WatchRun: Codable, Hashable, Identifiable {
    /// Becomes the phone's `Run.id`, so a transfer delivered twice is recorded once.
    var id: UUID
    /// Nil for a free run.
    var plannedSessionID: UUID?
    var startedAt: Date
    var endedAt: Date
    var activeDuration: TimeInterval
    var distanceMeters: Double
    var segments: [RecordedSegment]
    var route: [RouteSample]
    var averageHeartRate: Double?
    var maxHeartRate: Double?
}
