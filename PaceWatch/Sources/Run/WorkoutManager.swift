import Foundation
import HealthKit

/// Runs an HKWorkoutSession for the length of a run: it keeps the app alive
/// with the wrist down (timer, GPS, haptics) and streams heart rate.
///
/// The workout itself is discarded at the end rather than saved to Health —
/// Pace keeps runs in its own store; Health export is a separate decision.
@MainActor
final class WorkoutManager: NSObject, ObservableObject {
    @Published private(set) var heartRate: Double?
    @Published private(set) var averageHeartRate: Double?
    @Published private(set) var maxHeartRate: Double?
    /// Every reading of the run, to average each segment at the end.
    private(set) var heartRateSamples: [HeartRateSample] = []

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var heartRateSum = 0.0
    private var heartRateCount = 0

    nonisolated private static let heartRateType = HKQuantityType(.heartRate)
    nonisolated private static let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

    /// Starts the workout once HealthKit has answered. Without permission the
    /// run still works — only while the screen is up, and without heart rate.
    func start() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [Self.heartRateType])

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor
        guard let session = try? HKWorkoutSession(healthStore: store, configuration: configuration) else { return }
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
        builder.delegate = self
        self.session = session
        self.builder = builder

        let start = Date.now
        session.startActivity(with: start)
        try? await builder.beginCollection(at: start)
    }

    func setPaused(_ paused: Bool) {
        paused ? session?.pause() : session?.resume()
    }

    func end() {
        guard let session, let builder else { return }
        self.session = nil
        self.builder = nil
        session.end()
        Task {
            try? await builder.endCollection(at: .now)
            builder.discardWorkout()
        }
    }

    private func record(_ statistics: HKStatistics) {
        guard let latest = statistics.mostRecentQuantity()?.doubleValue(for: Self.beatsPerMinute) else { return }
        heartRate = latest
        let takenAt = statistics.mostRecentQuantityDateInterval()?.end ?? .now
        heartRateSamples.append(HeartRateSample(timestamp: takenAt, beatsPerMinute: latest))
        heartRateSum += latest
        heartRateCount += 1
        maxHeartRate = max(maxHeartRate ?? 0, latest)
        averageHeartRate = statistics.averageQuantity()?.doubleValue(for: Self.beatsPerMinute) ?? heartRateSum / Double(heartRateCount)
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard collectedTypes.contains(Self.heartRateType), let statistics = workoutBuilder.statistics(for: Self.heartRateType) else { return }
        Task { @MainActor in self.record(statistics) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
