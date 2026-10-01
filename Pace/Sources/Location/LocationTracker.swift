import Foundation
import CoreLocation
import Combine

/// Wraps CLLocationManager for foreground + locked-screen background tracking.
/// Shared with the Watch app, where an active workout session keeps it running.
/// Accuracy/battery balance: best accuracy while a run is active, filtered by
/// a distance filter and an accuracy/speed sanity check to reject GPS jumps.
@MainActor
final class LocationTracker: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var currentSpeed: Double = 0 // meters/sec
    @Published private(set) var recordedPoints: [RouteSample] = []

    private let manager = CLLocationManager()
    /// Cumulative distance at each accepted fix, so any stretch of the run
    /// (an interval, a free-run segment) can be measured after the fact.
    private var distanceSamples: [(date: Date, meters: Double)] = []
    private var lastAcceptedLocation: CLLocation?
    /// A fix rejected as a jump from `lastAcceptedLocation`. If the next fix is
    /// consistent with it, the old anchor was the bad one (e.g. a stale cached
    /// fix), so tracking re-anchors here instead of rejecting forever.
    private var pendingAnchor: CLLocation?
    private var trackingStartedAt = Date.distantPast
    private var isPaused = false

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        #if os(iOS)
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        #endif
    }

    func requestAuthorization() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func requestAlwaysAuthorizationForBackgroundRun() {
        manager.requestAlwaysAuthorization()
    }

    func startTracking() {
        distanceMeters = 0
        currentSpeed = 0
        recordedPoints = []
        distanceSamples = []
        lastAcceptedLocation = nil
        pendingAnchor = nil
        isPaused = false
        trackingStartedAt = .now
        // With the `location` background mode, updates started in the foreground
        // keep flowing while the phone is locked under When-In-Use authorization too.
        updateBackgroundUpdates(enabled: true)
        manager.startUpdatingLocation()
    }

    /// Movement while paused isn't part of the run; on resume, distance picks up
    /// from the next fix rather than bridging the gap.
    func setPaused(_ paused: Bool) {
        isPaused = paused
        if !paused {
            lastAcceptedLocation = nil
            pendingAnchor = nil
        }
    }

    func stopTracking() {
        updateBackgroundUpdates(enabled: false)
        manager.stopUpdatingLocation()
    }

    /// iPhone only: the `location` background mode keeps fixes flowing while
    /// locked. On the Watch the workout session does that, and setting this
    /// without the `location` mode would trap.
    private func updateBackgroundUpdates(enabled: Bool) {
        #if os(iOS)
        let status = manager.authorizationStatus
        manager.allowsBackgroundLocationUpdates = enabled && (status == .authorizedWhenInUse || status == .authorizedAlways)
        #endif
    }

    /// Distance covered by `date`, interpolated between fixes. Flat across
    /// pauses, since no distance is counted while paused.
    func distance(at date: Date) -> Double {
        guard let after = distanceSamples.firstIndex(where: { $0.date > date }) else {
            return distanceSamples.last?.meters ?? 0
        }
        guard after > 0 else { return 0 }
        let a = distanceSamples[after - 1], b = distanceSamples[after]
        let span = b.date.timeIntervalSince(a.date)
        guard span > 0 else { return b.meters }
        return a.meters + (b.meters - a.meters) * date.timeIntervalSince(a.date) / span
    }
}

extension LocationTracker: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            // Permission is often granted after tracking already started on first run.
            self.updateBackgroundUpdates(enabled: true)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations {
                accept(location)
            }
        }
    }

    private func accept(_ location: CLLocation) {
        guard !isPaused else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 30 else { return }
        // Cached fixes delivered on start can be from wherever the phone last was.
        guard location.timestamp > trackingStartedAt.addingTimeInterval(-5) else { return }

        if let last = lastAcceptedLocation {
            if Self.isPlausibleMove(from: last, to: location) {
                distanceMeters += location.distance(from: last)
                pendingAnchor = nil
            } else if let pending = pendingAnchor, Self.isPlausibleMove(from: pending, to: location) {
                // Two consistent fixes agree with each other, not with the anchor:
                // re-anchor without counting the jump as distance. A lone bad
                // starting fix is dropped so it doesn't distort the route map.
                if recordedPoints.count == 1 { recordedPoints.removeAll() }
                record(pending)
                distanceMeters += location.distance(from: pending)
                pendingAnchor = nil
            } else {
                pendingAnchor = location
                return
            }
        }
        lastAcceptedLocation = location
        currentSpeed = max(location.speed, 0)
        record(location)
        distanceSamples.append((location.timestamp, distanceMeters))
    }

    private func record(_ location: CLLocation) {
        recordedPoints.append(RouteSample(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed,
            course: location.course
        ))
    }

    /// Rejects points implying an unrealistic sprint (GPS jump).
    private static func isPlausibleMove(from previous: CLLocation, to next: CLLocation) -> Bool {
        let elapsed = next.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else { return false }
        return next.distance(from: previous) / elapsed <= 8
    }
}
