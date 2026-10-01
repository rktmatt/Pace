import Foundation
import SwiftData

enum CompletionState: String, Codable {
    case planned, completed, skipped
}

/// The user's active instance of a bundled ProgramDefinition.
@Model
final class ActiveProgram {
    @Attribute(.unique) var id: UUID
    /// Matches ProgramDefinition.id — the static definition is looked up, never duplicated.
    var definitionID: String
    var startedAt: Date
    var currentWeek: Int
    var lastFeedback: String?
    /// Which revision of the bundled program the scheduled sessions were built
    /// from; see `ProgramCoordinator.migrateToCurrentProgramVersion`.
    var programVersion: Int = 1

    init(definitionID: String, startedAt: Date = .now, currentWeek: Int = 1) {
        self.id = UUID()
        self.definitionID = definitionID
        self.startedAt = startedAt
        self.currentWeek = currentWeek
        self.lastFeedback = nil
    }
}

/// A concrete, dated occurrence of a SessionDefinition, scheduled onto the user's calendar.
/// Adaptation moves these around; the underlying ProgramDefinition never changes.
@Model
final class PlannedSession: Identifiable {
    @Attribute(.unique) var id: UUID
    var week: Int
    var scheduledAt: Date
    var kindRaw: String
    var title: String
    var intervals: [IntervalDefinition]
    var stateRaw: String
    /// Why the weekly check changed this session ("Runs 10% shorter after…"),
    /// shown on the Plan and on the recap. Nil when it's as the program wrote it.
    var adjustmentNote: String?

    var kind: SessionKind { SessionKind(rawValue: kindRaw) ?? .easy }
    var state: CompletionState { get { CompletionState(rawValue: stateRaw) ?? .planned } set { stateRaw = newValue.rawValue } }
    var plannedDurationSeconds: Int { intervals.reduce(0) { $0 + $1.durationSeconds * $1.repeatCount } }

    init(week: Int, scheduledAt: Date, kind: SessionKind, title: String, intervals: [IntervalDefinition]) {
        self.id = UUID()
        self.week = week
        self.scheduledAt = scheduledAt
        self.kindRaw = kind.rawValue
        self.title = title
        self.intervals = intervals
        self.stateRaw = CompletionState.planned.rawValue
    }
}

/// What a weekly check (or a restart / program update) did — the history of
/// adjustments, kept instead of overwriting the last message.
enum AdaptationKind: String, Codable {
    case onPlan, aligned, repeated, lighter, held, restarted, programUpdated

    init(_ adaptation: Adaptation) {
        switch adaptation {
        case .unchanged: self = .onPlan
        case .alignSchedule: self = .aligned
        case .repeatCurrentWeek: self = .repeated
        case .reduceNextWeek: self = .lighter
        case .holdProgression: self = .held
        }
    }

    var label: String {
        switch self {
        case .onPlan: "ON PLAN"
        case .aligned: "DAYS MOVED"
        case .repeated: "WEEK REPEATED"
        case .lighter: "LIGHTER WEEK"
        case .held: "HELD STEADY"
        case .restarted: "NEW START"
        case .programUpdated: "PROGRAM UPDATED"
        }
    }

    /// Home banner heading for the latest record.
    var headline: String {
        switch self {
        case .onPlan: "Week wrapped up"
        case .restarted: "Fresh start"
        case .programUpdated: "Program updated"
        default: "Your plan has adjusted"
        }
    }
}

@Model
final class AdaptationRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    /// The program week evaluated (or restarted at).
    var week: Int
    var kindRaw: String
    var plannedSessions: Int
    var completedSessions: Int
    var plannedMinutes: Int
    var actualMinutes: Int
    var message: String

    var kind: AdaptationKind { AdaptationKind(rawValue: kindRaw) ?? .onPlan }
    var hasNumbers: Bool { plannedSessions > 0 }

    init(date: Date = .now, week: Int, kind: AdaptationKind, snapshot: TrainingSnapshot? = nil, message: String) {
        self.id = UUID()
        self.date = date
        self.week = week
        self.kindRaw = kind.rawValue
        self.plannedSessions = snapshot?.plannedSessions ?? 0
        self.completedSessions = snapshot?.completedSessions ?? 0
        self.plannedMinutes = snapshot?.plannedMinutes ?? 0
        self.actualMinutes = snapshot?.actualMinutes ?? 0
        self.message = message
    }
}

@Model
final class Run {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date
    var distanceMeters: Double
    /// Time actually spent running, excluding pauses. Optional so older stores migrate.
    var activeDuration: TimeInterval?
    var sessionKindRaw: String
    var plannedSessionID: UUID?
    @Relationship(deleteRule: .cascade) var routePoints: [RoutePoint]
    /// Each run/walk stretch as actually performed. Optional so older stores migrate.
    var segments: [RecordedSegment]?
    /// Heart rate in beats per minute, recorded only by runs done on the Watch.
    var averageHeartRate: Double?
    var maxHeartRate: Double?

    var duration: TimeInterval { activeDuration ?? endedAt.timeIntervalSince(startedAt) }
    var sessionKind: SessionKind { SessionKind(rawValue: sessionKindRaw) ?? .easy }
    var averagePaceSecondsPerKm: Double? {
        guard distanceMeters > 0 else { return nil }
        return duration / (distanceMeters / 1000)
    }

    init(id: UUID = UUID(), startedAt: Date, endedAt: Date, activeDuration: TimeInterval? = nil, distanceMeters: Double, sessionKind: SessionKind, plannedSessionID: UUID? = nil, routePoints: [RoutePoint] = [], segments: [RecordedSegment] = []) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.activeDuration = activeDuration
        self.distanceMeters = distanceMeters
        self.sessionKindRaw = sessionKind.rawValue
        self.plannedSessionID = plannedSessionID
        self.routePoints = routePoints
        self.segments = segments
    }
}

@Model
final class RoutePoint {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var horizontalAccuracy: Double
    var speed: Double
    var course: Double

    init(timestamp: Date, latitude: Double, longitude: Double, altitude: Double, horizontalAccuracy: Double, speed: Double, course: Double) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.course = course
    }

    convenience init(_ sample: RouteSample) {
        self.init(timestamp: sample.timestamp, latitude: sample.latitude, longitude: sample.longitude, altitude: sample.altitude, horizontalAccuracy: sample.horizontalAccuracy, speed: sample.speed, course: sample.course)
    }
}
