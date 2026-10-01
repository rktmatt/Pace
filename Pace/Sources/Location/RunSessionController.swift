import Foundation
import Combine

/// Drives an active run: elapsed time, current interval progress, and cue
/// dispatch. Owns no persistence — the view saves a Run once this reports done.
///
/// Two modes: a planned session follows its interval timeline and finishes on
/// its own; a free run has no plan — the runner switches between run and walk
/// whenever they like and ends it themselves. Both record the segments as
/// actually performed.
///
/// Time is derived from wall-clock dates rather than counting timer ticks, so a
/// suspended or throttled timer (locked phone) can't make the session drift.
@MainActor
final class RunSessionController: ObservableObject {
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var currentIntervalIndex: Int = 0
    @Published private(set) var timeRemainingInInterval: TimeInterval = 0
    @Published private(set) var isFinished = false
    @Published private(set) var isPaused = false
    /// Free run only: the effort the runner is in now.
    @Published private(set) var freeKind: IntervalKind = .walk
    /// Segments completed so far, excluding the one in progress.
    @Published private(set) var segments: [RecordedSegment] = []
    /// The segment in progress when the run was ended early, closed by `stop()`.
    /// Kept out of `segments` so the run screen doesn't change while it fades out.
    private var finalSegment: RecordedSegment?

    /// Everything performed, for saving once the run has stopped.
    var recordedSegments: [RecordedSegment] { segments + [finalSegment].compactMap { $0 } }

    let isFreeRun: Bool
    let expandedIntervals: [IntervalDefinition]
    /// Elapsed time at which each expanded interval ends.
    private let intervalEnds: [TimeInterval]
    private var startedAt: Date?
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0
    private var segmentStart: (date: Date, elapsed: TimeInterval)?
    private var isStopped = false
    private var timer: AnyCancellable?
    private let sound = SoundCueService()
    /// Seconds-left value of the last 3-2-1 tick played, so each sounds once.
    private var lastCountdownSecond: Int?
    /// Index of the final run in a session with more than one, named when announced.
    private let lastRunIndex: Int?
    /// Elapsed time announced as the session's midpoint; nil for free runs and
    /// sessions too short for it to mean anything.
    private let halfwayMark: TimeInterval?
    private var halfwayAnnounced = false
    /// Whole minutes left in the current interval at the last minute cue (or at
    /// its start), so each mark sounds once.
    private var lastMinutesLeft = 0

    init(session: PlannedSession) {
        isFreeRun = false
        expandedIntervals = session.intervals.timeline
        var runningTotal: TimeInterval = 0
        intervalEnds = expandedIntervals.map { interval in
            runningTotal += TimeInterval(interval.durationSeconds)
            return runningTotal
        }
        timeRemainingInInterval = expandedIntervals.first.map { TimeInterval($0.durationSeconds) } ?? 0
        let timeline = expandedIntervals
        let runIndices = timeline.indices.filter { timeline[$0].kind == .run }
        lastRunIndex = runIndices.count > 1 ? runIndices.last : nil
        halfwayMark = Self.halfwayMark(intervalEnds: intervalEnds)
        lastMinutesLeft = Self.minutesLeft(timeRemainingInInterval)
    }

    /// A free run starts walking: most runners ease in, and the first switch
    /// to running is then a deliberate tap.
    init(freeRunStartingWith kind: IntervalKind = .walk) {
        isFreeRun = true
        expandedIntervals = []
        intervalEnds = []
        freeKind = kind
        lastRunIndex = nil
        halfwayMark = nil
    }

    var totalDuration: TimeInterval { intervalEnds.last ?? 0 }

    var currentKind: IntervalKind? { isFreeRun ? freeKind : currentInterval?.kind }

    var currentInterval: IntervalDefinition? {
        guard currentIntervalIndex < expandedIntervals.count else { return nil }
        return expandedIntervals[currentIntervalIndex]
    }

    var nextInterval: IntervalDefinition? {
        let next = currentIntervalIndex + 1
        guard next < expandedIntervals.count else { return nil }
        return expandedIntervals[next]
    }

    /// Free run: time spent in the current segment so far.
    var timeInSegment: TimeInterval {
        elapsed - (segmentStart?.elapsed ?? 0)
    }

    /// 0...1 progress through the current segment.
    var intervalProgress: Double {
        guard let interval = currentInterval, interval.durationSeconds > 0 else { return 1 }
        return 1 - timeRemainingInInterval / TimeInterval(interval.durationSeconds)
    }

    func start() {
        let now = Date.now
        if isFreeRun {
            sound.announce(switchTo: freeKind)
        } else {
            guard let first = expandedIntervals.first else { isFinished = true; return }
            announce(intervalAt: 0)
        }
        startedAt = now
        segmentStart = (now, 0)
        timer = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func togglePause() {
        if let pausedAt {
            pausedTotal += Date.now.timeIntervalSince(pausedAt)
            self.pausedAt = nil
            isPaused = false
            sound.announceResume()
        } else {
            pausedAt = .now
            isPaused = true
            sound.announcePause()
        }
    }

    /// Free run: close the current segment and start one of the other effort.
    func switchFreeKind() {
        guard isFreeRun, !isPaused, !isFinished else { return }
        tick()
        closeSegment(kind: freeKind, at: .now, elapsed: elapsed)
        freeKind = freeKind == .run ? .walk : .run
        sound.announce(switchTo: freeKind)
    }

    /// Idempotent: the view stops on finish and again when it disappears, which
    /// may be minutes later while the recap is up.
    func stop() {
        guard !isStopped else { return }
        tick()
        isStopped = true
        timer?.cancel()
        if let kind = currentKind, !isFinished, let start = segmentStart, elapsed - start.elapsed >= 1 {
            finalSegment = RecordedSegment(kind: kind, startedAt: start.date, endedAt: pausedAt ?? .now, activeDuration: elapsed - start.elapsed)
        }
    }

    private func tick() {
        guard let startedAt, !isFinished, !isStopped else { return }
        let now = pausedAt ?? .now
        elapsed = max(0, now.timeIntervalSince(startedAt) - pausedTotal)
        guard !isFreeRun else { return }

        let index = intervalEnds.firstIndex { $0 > elapsed } ?? expandedIntervals.count
        // Close every planned segment passed since the last tick, dating each
        // boundary back from now so a long suspension doesn't blur them together.
        for passed in currentIntervalIndex..<min(index, expandedIntervals.count) {
            let end = intervalEnds[passed]
            closeSegment(kind: expandedIntervals[passed].kind, at: now.addingTimeInterval(end - elapsed), elapsed: end)
        }
        if index >= expandedIntervals.count {
            currentIntervalIndex = expandedIntervals.count
            timeRemainingInInterval = 0
            isFinished = true
            let runningSeconds = expandedIntervals.filter { $0.kind == .run }.reduce(0) { $0 + $1.durationSeconds }
            sound.announceCompletion(runningSeconds: runningSeconds)
            timer?.cancel()
            return
        }
        timeRemainingInInterval = intervalEnds[index] - elapsed
        let halfwayRemaining = halfwayRemainingIfDue()
        if index != currentIntervalIndex {
            // After a long suspension several segments may have passed; only
            // the one the runner is in now is worth announcing.
            currentIntervalIndex = index
            lastCountdownSecond = nil
            lastMinutesLeft = Self.minutesLeft(timeRemainingInInterval)
            announce(intervalAt: index, halfwayRemaining: halfwayRemaining)
        } else if let halfwayRemaining {
            // Takes precedence over a minute mark landing on the same tick:
            // both are information, and two cues back to back would be noise.
            lastMinutesLeft = Self.minutesLeft(timeRemainingInInterval)
            sound.announceHalfway(remainingSeconds: halfwayRemaining)
        } else if !playMinuteMarkIfDue() {
            playCountdownIfDue(intervalIndex: index)
        }
    }

    private func announce(intervalAt index: Int, halfwayRemaining: Int? = nil) {
        sound.announce(transitionTo: expandedIntervals[index], isLastRun: index == lastRunIndex, halfwayRemaining: halfwayRemaining)
    }

    /// Seconds left in the session when its midpoint has just been crossed.
    /// Marked as done either way, so a midpoint passed during a long suspension
    /// isn't announced late.
    private func halfwayRemainingIfDue() -> Int? {
        guard !halfwayAnnounced, let halfwayMark, elapsed >= halfwayMark else { return nil }
        halfwayAnnounced = true
        guard elapsed - halfwayMark < 5 else { return nil }
        return Int((totalDuration - halfwayMark).rounded())
    }

    /// "4 minutes left" as each whole minute of an interval passes. The start
    /// of the interval already states its length, so it's never repeated here.
    /// - Returns: whether a cue was played.
    private func playMinuteMarkIfDue() -> Bool {
        guard !isPaused else { return false }
        let minutes = Self.minutesLeft(timeRemainingInInterval)
        guard minutes < lastMinutesLeft else { return false }
        lastMinutesLeft = minutes
        // Only right at the mark: after a suspension the number would be stale.
        guard TimeInterval(minutes * 60) - timeRemainingInInterval < 5 else { return false }
        sound.announceMinutesLeft(minutes)
        return true
    }

    /// Whole minutes that will still be left once the current minute runs out:
    /// 4 from 4:00 down to 3:01.
    static func minutesLeft(_ remaining: TimeInterval) -> Int {
        Int((remaining / 60).rounded(.up))
    }

    /// The session's midpoint by time, snapped to an interval switch within
    /// 15 seconds of it — symmetric run/walk sessions usually have one — so the
    /// two cues merge into one instead of talking over each other.
    static func halfwayMark(intervalEnds: [TimeInterval]) -> TimeInterval? {
        guard let total = intervalEnds.last, total >= 4 * 60 else { return nil }
        let half = total / 2
        let nearestSwitch = intervalEnds.dropLast().min { abs($0 - half) < abs($1 - half) }
        if let nearestSwitch, abs(nearestSwitch - half) <= 15 { return nearestSwitch }
        return half
    }

    /// Ticks at 3, 2 and 1 seconds before every switch (and before the end), so
    /// the change is expected rather than startling. Skipped for intervals too
    /// short for a countdown to be anything but noise.
    private func playCountdownIfDue(intervalIndex index: Int) {
        guard !isPaused, expandedIntervals[index].durationSeconds >= 10 else { return }
        let secondsLeft = Int(timeRemainingInInterval.rounded(.up))
        guard (1...3).contains(secondsLeft), secondsLeft != lastCountdownSecond else { return }
        lastCountdownSecond = secondsLeft
        sound.countdownTick()
    }

    private func closeSegment(kind: IntervalKind, at date: Date, elapsed end: TimeInterval) {
        guard let start = segmentStart else { return }
        if end - start.elapsed >= 1 {
            segments.append(RecordedSegment(kind: kind, startedAt: start.date, endedAt: date, activeDuration: end - start.elapsed))
        }
        segmentStart = (date, end)
    }
}
