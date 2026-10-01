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
    /// Mean heart rate over the segment, only for runs done on the Watch.
    var averageHeartRate: Double?

    var paceSecondsPerKm: Double? {
        guard distanceMeters > 0, activeDuration > 0 else { return nil }
        return activeDuration / (distanceMeters / 1000)
    }
}

/// One heart-rate reading taken during a run on the Watch. The run keeps a
/// downsampled series for the recap's heart-rate line and averages each segment.
struct HeartRateSample: Codable, Hashable {
    var timestamp: Date
    var beatsPerMinute: Double
}

extension Array where Element == HeartRateSample {
    /// One averaged reading per `interval` seconds — enough for the recap's
    /// line (~180 points for 30 minutes) and small enough to sync and store.
    func downsampled(every interval: TimeInterval) -> [HeartRateSample] {
        guard let first = first?.timestamp else { return [] }
        let buckets = Dictionary(grouping: self) { Int($0.timestamp.timeIntervalSince(first) / interval) }
        return buckets.keys.sorted().compactMap { key in
            guard let readings = buckets[key], !readings.isEmpty else { return nil }
            let mean = readings.reduce(0) { $0 + $1.beatsPerMinute } / Double(readings.count)
            let time = readings.reduce(0) { $0 + $1.timestamp.timeIntervalSince(first) } / Double(readings.count)
            return HeartRateSample(timestamp: first.addingTimeInterval(time), beatsPerMinute: mean)
        }
    }

    /// Mean of the readings taken within `start...end`, or nil when there are none.
    func averageBeatsPerMinute(from start: Date, to end: Date) -> Double? {
        let inside = filter { $0.timestamp >= start && $0.timestamp <= end }
        guard !inside.isEmpty else { return nil }
        return inside.reduce(0) { $0 + $1.beatsPerMinute } / Double(inside.count)
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
