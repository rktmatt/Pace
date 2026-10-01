import Foundation

/// One stretch of a finished run at a single effort — a planned interval as it
/// was actually done, or a run/walk switch the runner made in a free run.
struct RecordedSegment: Codable, Hashable {
    var kind: IntervalKind
    var startedAt: Date
    var endedAt: Date
    /// Time spent in the segment, excluding pauses.
    var activeDuration: TimeInterval
    var distanceMeters: Double = 0

    var paceSecondsPerKm: Double? {
        guard distanceMeters > 0, activeDuration > 0 else { return nil }
        return activeDuration / (distanceMeters / 1000)
    }
}

/// One accepted GPS fix, as recorded during a run. A plain value so the run
/// engine works on the Watch (no SwiftData there) and survives the transfer to
/// the phone; the phone stores it as a `RoutePoint`.
struct RouteSample: Codable, Hashable {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var horizontalAccuracy: Double
    var speed: Double
    var course: Double
}
