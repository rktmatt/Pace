import XCTest
import SwiftData
@testable import Pace

final class IntervalTimelineTests: XCTestCase {
    func testRepeatedRunWalkPairsAlternate() {
        let intervals = [
            IntervalDefinition(kind: .warmup, durationSeconds: 300),
            IntervalDefinition(kind: .run, durationSeconds: 60, repeatCount: 8),
            IntervalDefinition(kind: .walk, durationSeconds: 90, repeatCount: 8),
            IntervalDefinition(kind: .cooldown, durationSeconds: 300),
        ]
        let kinds = intervals.timeline.map(\.kind)
        XCTAssertEqual(kinds.count, 18)
        XCTAssertEqual(kinds.first, .warmup)
        XCTAssertEqual(kinds.last, .cooldown)
        XCTAssertEqual(Array(kinds[1...4]), [.run, .walk, .run, .walk])
    }

    func testTimelineTotalMatchesPlannedDuration() {
        for week in Couch5KProgram.definition.weeks {
            let session = week.sessions[0]
            XCTAssertEqual(session.intervals.timeline.reduce(0) { $0 + $1.durationSeconds }, session.totalDurationSeconds)
        }
    }
}

/// Guards the program's progression policy (see `Couch5KProgram`): every
/// session's longest run and total running time stay a small step from the
/// biggest seen so far.
final class ProgramTests: XCTestCase {
    private var sessions: [SessionDefinition] { Couch5KProgram.definition.weeks.flatMap(\.sessions) }

    func testLongestRunNeverSpikes() {
        var peak = sessions[0].intervals.longestRunSeconds
        for session in sessions {
            let longest = session.intervals.longestRunSeconds
            XCTAssertLessThanOrEqual(Double(longest), max(Double(peak) * 1.2, Double(peak + 120)), "\(session.title): longest run \(longest)s after peak \(peak)s")
            peak = max(peak, longest)
        }
        XCTAssertEqual(peak, 30 * 60)
    }

    func testRunningTimeNeverSpikes() {
        var peak = sessions[0].intervals.runningSeconds
        for session in sessions {
            let running = session.intervals.runningSeconds
            XCTAssertLessThanOrEqual(Double(running), max(Double(peak) * 1.25, Double(peak + 120)), "\(session.title): \(running)s running after peak \(peak)s")
            peak = max(peak, running)
        }
    }

    func testSessionsStayBetweenHalfAnHourAndFortyMinutes() {
        for session in sessions {
            XCTAssertTrue((25 * 60...40 * 60).contains(session.totalDurationSeconds), "\(session.title): \(session.totalDurationSeconds)s")
        }
    }

    func testEveryWeekHasThreeSessions() {
        XCTAssertEqual(Couch5KProgram.definition.weeks.map(\.sessions.count), Array(repeating: 3, count: 9))
    }
}

final class AdaptationEngineTests: XCTestCase {
    private func snapshot(planned: Int = 3, completed: Int, plannedMinutes: Int = 90, actualMinutes: Int, actualDays: [Int] = [1, 3, 5], scheduledDays: [Int] = [1, 3, 5]) -> TrainingSnapshot {
        TrainingSnapshot(plannedSessions: planned, completedSessions: completed, plannedMinutes: plannedMinutes, actualMinutes: actualMinutes, actualWeekdays: actualDays, scheduledWeekdays: scheduledDays)
    }

    func testOneOfThreeRepeatsTheWeek() {
        XCTAssertEqual(AdaptationEngine().decide(for: snapshot(completed: 1, actualMinutes: 30, actualDays: [1])).adaptation, .repeatCurrentWeek)
    }

    func testNothingDoneRepeatsTheWeek() {
        XCTAssertEqual(AdaptationEngine().decide(for: snapshot(completed: 0, actualMinutes: 0, actualDays: [])).adaptation, .repeatCurrentWeek)
    }

    func testTwoOfThreeReducesNextWeek() {
        XCTAssertEqual(AdaptationEngine().decide(for: snapshot(completed: 2, actualMinutes: 60, actualDays: [1, 3])).adaptation, .reduceNextWeek(by: 0.10))
    }

    func testOverVolumeHoldsProgression() {
        XCTAssertEqual(AdaptationEngine().decide(for: snapshot(completed: 3, actualMinutes: 130)).adaptation, .holdProgression)
    }

    func testOnPlanIsUnchanged() {
        XCTAssertEqual(AdaptationEngine().decide(for: snapshot(completed: 3, actualMinutes: 90)).adaptation, .unchanged)
    }

    func testDifferentDaysAlignSchedule() {
        XCTAssertEqual(AdaptationEngine().decide(for: snapshot(completed: 3, actualMinutes: 90, actualDays: [2, 4, 6])).adaptation, .alignSchedule(toWeekdays: [2, 4, 6]))
    }
}

@MainActor
final class AdaptationApplierTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try ModelContainer(
            for: ActiveProgram.self, PlannedSession.self, Run.self, RoutePoint.self, AdaptationRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Monday 2026-09-07, UTC.
    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 7))! }

    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: monday)! }

    private func schedule(weeks: Int) -> [PlannedSession] {
        let sessions = ProgramScheduler.plannedSessions(for: Couch5KProgram.definition, startingFrom: monday, calendar: calendar)
            .filter { $0.week <= weeks }
        sessions.forEach(context.insert)
        return sessions
    }

    func testRepeatWeekCopiesIntoFollowingWeekAndShiftsTheRest() {
        let sessions = schedule(weeks: 3)
        let week2Starts = sessions.filter { $0.week == 2 }.map(\.scheduledAt)
        let week3Before = sessions.filter { $0.week == 3 }.map(\.scheduledAt)

        let created = AdaptationApplier.apply(.repeatCurrentWeek, currentWeek: 2, to: sessions, today: day(13), calendar: calendar)

        XCTAssertEqual(created.count, 3)
        XCTAssertTrue(created.allSatisfy { $0.week == 2 })
        XCTAssertEqual(created.map(\.scheduledAt), week2Starts.map { calendar.date(byAdding: .day, value: 7, to: $0)! })
        XCTAssertEqual(sessions.filter { $0.week == 3 }.map(\.scheduledAt), week3Before.map { calendar.date(byAdding: .day, value: 7, to: $0)! })
    }

    func testRepeatAfterLongBreakLandsInCurrentWeek() {
        let sessions = schedule(weeks: 2)
        let today = day(7 * 5 + 2) // Wednesday, five weeks after week 1 started
        let created = AdaptationApplier.apply(.repeatCurrentWeek, currentWeek: 1, to: sessions, today: today, calendar: calendar)

        XCTAssertEqual(created.map { calendar.startOfISOWeek(for: $0.scheduledAt) }, Array(repeating: calendar.startOfISOWeek(for: today), count: 3))
    }

    func testCurrentBlockIgnoresEarlierAttemptOfRepeatedWeek() {
        let sessions = schedule(weeks: 2)
        let created = AdaptationApplier.apply(.repeatCurrentWeek, currentWeek: 1, to: sessions, today: day(6), calendar: calendar)
        created.forEach(context.insert)

        let block = TrainingAnalyzer.currentBlock(week: 1, of: sessions + created, calendar: calendar)
        XCTAssertEqual(Set(block.map(\.id)), Set(created.map(\.id)))
    }

    func testReduceNextWeekOnlyShortensRunSegments() {
        let sessions = schedule(weeks: 2)
        let before = sessions.first { $0.week == 2 }!.intervals

        AdaptationApplier.apply(.reduceNextWeek(by: 0.10), currentWeek: 1, to: sessions, calendar: calendar)

        let after = sessions.first { $0.week == 2 }!.intervals
        for (old, new) in zip(before, after) {
            if old.kind == .run {
                XCTAssertEqual(new.durationSeconds, Int(Double(old.durationSeconds) * 0.9))
            } else {
                XCTAssertEqual(new.durationSeconds, old.durationSeconds)
            }
        }
        let week1 = sessions.first { $0.week == 1 }!.intervals.map(\.durationSeconds)
        XCTAssertEqual(week1, Couch5KProgram.definition.weeks[0].sessions[0].intervals.map(\.durationSeconds))
    }

    func testMissedWeekIsSkippedRepeatedAndNotOfferedAgain() {
        let coordinator = ProgramCoordinator(context: context)
        let program = ActiveProgram(definitionID: Couch5KProgram.definition.id)
        context.insert(program)
        // A program started three weeks ago with nothing done.
        let start = Calendar.current.date(byAdding: .day, value: -21, to: .now)!
        ProgramScheduler.plannedSessions(for: Couch5KProgram.definition, startingFrom: start).forEach(context.insert)

        coordinator.evaluateWeeksIfNeeded(program: program)

        let sessions = try! context.fetch(FetchDescriptor<PlannedSession>())
        XCTAssertEqual(program.currentWeek, 1)
        let next = coordinator.todaysSession(allSessions: sessions)!
        XCTAssertEqual(next.week, 1)
        XCTAssertGreaterThanOrEqual(next.scheduledAt, Calendar.current.startOfISOWeek(for: .now))
        XCTAssertGreaterThanOrEqual(sessions.filter { $0.week == 1 && $0.state == .skipped }.count, 3)
    }

    private func weekday(_ isoWeekday: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: isoWeekday - 1, to: Calendar.current.startOfISOWeek(for: .now))!
    }

    func testRestartAtWeekReplacesUpcomingAndKeepsCompleted() {
        let coordinator = ProgramCoordinator(context: context)
        coordinator.ensureProgramSeeded()
        let program = coordinator.activeProgram()!
        let done = try! context.fetch(FetchDescriptor<PlannedSession>()).first { $0.week == 1 }!
        done.state = .completed

        coordinator.restartProgram(atWeek: 4, today: weekday(3))

        let sessions = try! context.fetch(FetchDescriptor<PlannedSession>())
        XCTAssertEqual(program.currentWeek, 4)
        XCTAssertEqual(try! context.fetch(FetchDescriptor<AdaptationRecord>()).map(\.kind), [.restarted])
        XCTAssertTrue(sessions.contains { $0.id == done.id })
        XCTAssertEqual(sessions.filter { $0.state != .completed }.map(\.week).min(), 4)
        XCTAssertEqual(sessions.filter { $0.week == 9 }.count, 3)
    }

    func testMidWeekRestartPacksPassedSessionsIntoRemainingDays() {
        let coordinator = ProgramCoordinator(context: context)
        let schedule = coordinator.restartSchedule(atWeek: 4, today: weekday(4)) // Thursday
        let week4 = schedule.filter { $0.week == 4 }.map { Calendar.current.isoWeekday(of: $0.scheduledAt) }.sorted()
        XCTAssertEqual(week4, [4, 5, 6])
        XCTAssertTrue(schedule.filter { $0.week == 4 }.allSatisfy { $0.scheduledAt >= Calendar.current.startOfISOWeek(for: weekday(4)) })
        let week5Start = schedule.filter { $0.week == 5 }.map(\.scheduledAt).min()!
        XCTAssertEqual(Calendar.current.startOfISOWeek(for: week5Start), weekday(8))
    }

    func testRestartWithTooFewDaysLeftStartsNextMonday() {
        let coordinator = ProgramCoordinator(context: context)
        let schedule = coordinator.restartSchedule(atWeek: 2, today: weekday(6)) // Saturday
        let first = schedule.map(\.scheduledAt).min()!
        XCTAssertEqual(first, weekday(8))
    }

    func testRestartingAWeekAlreadyStartedThisWeekStartsNextMonday() {
        let coordinator = ProgramCoordinator(context: context)
        let done = PlannedSession(week: 2, scheduledAt: weekday(1), kind: .intervals, title: "Run/walk intervals", intervals: [])
        done.state = .completed
        context.insert(done)
        let first = coordinator.restartSchedule(atWeek: 2, today: weekday(2)).map(\.scheduledAt).min()!
        XCTAssertEqual(first, weekday(8))
    }

    func testFreeRunStaysOutsideTheProgram() {
        let coordinator = ProgramCoordinator(context: context)
        coordinator.ensureProgramSeeded()
        let segment = RecordedSegment(kind: .run, startedAt: .now, endedAt: .now.addingTimeInterval(120), activeDuration: 120, distanceMeters: 400)
        let run = coordinator.recordRun(startedAt: .now, endedAt: .now.addingTimeInterval(120), activeDuration: 120, distanceMeters: 400, routePoints: [], segments: [segment], for: nil)

        XCTAssertEqual(run.sessionKind, .free)
        XCTAssertNil(run.plannedSessionID)
        XCTAssertEqual(run.segments?.first?.paceSecondsPerKm, 300)
        let sessions = try! context.fetch(FetchDescriptor<PlannedSession>())
        XCTAssertTrue(sessions.allSatisfy { $0.state == .planned })
        XCTAssertEqual(TrainingAnalyzer.snapshot(week: 1, plannedSessions: sessions, runs: [run]).actualMinutes, 0)
    }

    private func watchRun(for sessionID: UUID?, id: UUID = UUID()) -> WatchRun {
        WatchRun(id: id, plannedSessionID: sessionID, startedAt: .now, endedAt: .now.addingTimeInterval(1200), activeDuration: 1200, distanceMeters: 2500, segments: [], route: [RouteSample(timestamp: .now, latitude: 48.85, longitude: 2.35, altitude: 35, horizontalAccuracy: 5, speed: 2, course: 0)], averageHeartRate: 142, maxHeartRate: 171)
    }

    func testWatchRunCompletesItsSessionOnce() {
        let coordinator = ProgramCoordinator(context: context)
        coordinator.ensureProgramSeeded()
        let session = try! context.fetch(FetchDescriptor<PlannedSession>(sortBy: [SortDescriptor(\.scheduledAt)])).first!
        let payload = watchRun(for: session.id)

        let run = coordinator.recordWatchRun(payload)
        XCTAssertEqual(run?.id, payload.id)
        XCTAssertEqual(run?.plannedSessionID, session.id)
        XCTAssertEqual(run?.averageHeartRate, 142)
        XCTAssertEqual(run?.routePoints.count, 1)
        XCTAssertEqual(session.state, .completed)

        // A redelivered transfer is ignored.
        XCTAssertNil(coordinator.recordWatchRun(payload))
        XCTAssertEqual(try! context.fetch(FetchDescriptor<Run>()).count, 1)
    }

    func testWatchRunForAnAlreadyCompletedSessionIsKeptAsFreeRun() {
        let coordinator = ProgramCoordinator(context: context)
        coordinator.ensureProgramSeeded()
        let session = try! context.fetch(FetchDescriptor<PlannedSession>(sortBy: [SortDescriptor(\.scheduledAt)])).first!
        coordinator.recordRun(startedAt: .now, endedAt: .now.addingTimeInterval(1200), activeDuration: 1200, distanceMeters: 2500, routePoints: [], for: session)

        let run = coordinator.recordWatchRun(watchRun(for: session.id))
        XCTAssertNil(run?.plannedSessionID)
        XCTAssertEqual(run?.sessionKind, .free)
    }

    func testMigrationRebuildsUpcomingSessionsInPlace() {
        let coordinator = ProgramCoordinator(context: context)
        coordinator.ensureProgramSeeded()
        let program = coordinator.activeProgram()!
        program.programVersion = 1
        let sessions = try! context.fetch(FetchDescriptor<PlannedSession>()).sorted { $0.scheduledAt < $1.scheduledAt }
        let old = [IntervalDefinition(kind: .run, durationSeconds: 480, repeatCount: 2)]
        sessions.forEach { $0.intervals = old }
        let done = sessions.first { $0.week == 5 }!
        done.state = .completed
        let dates = sessions.map(\.scheduledAt)

        coordinator.migrateToCurrentProgramVersion()

        XCTAssertEqual(program.programVersion, Couch5KProgram.version)
        XCTAssertNotNil(program.lastFeedback)
        XCTAssertEqual(sessions.map(\.scheduledAt), dates)
        XCTAssertEqual(done.intervals, old)
        let week5 = sessions.filter { $0.week == 5 }
        XCTAssertEqual(week5[1].intervals.map(\.durationSeconds), Couch5KProgram.definition.weeks[4].sessions[1].intervals.map(\.durationSeconds))
        XCTAssertEqual(week5[2].title, "Run/walk pyramid")

        program.lastFeedback = nil
        coordinator.migrateToCurrentProgramVersion()
        XCTAssertNil(program.lastFeedback, "runs once")
    }

    func testWeeklyCheckRecordsHistoryAndLabelsAdjustedSessions() {
        let coordinator = ProgramCoordinator(context: context)
        let program = ActiveProgram(definitionID: Couch5KProgram.definition.id)
        context.insert(program)
        // Week 1 ended last week with 2 of 3 sessions done → next week lighter.
        let start = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        ProgramScheduler.plannedSessions(for: Couch5KProgram.definition, startingFrom: start).forEach(context.insert)
        let week1 = try! context.fetch(FetchDescriptor<PlannedSession>()).filter { $0.week == 1 }.sorted { $0.scheduledAt < $1.scheduledAt }
        for session in week1.prefix(2) {
            session.state = .completed
            context.insert(Run(startedAt: session.scheduledAt, endedAt: session.scheduledAt, activeDuration: 1800, distanceMeters: 3000, sessionKind: .intervals, plannedSessionID: session.id))
        }

        coordinator.evaluateWeeksIfNeeded(program: program)

        let records = try! context.fetch(FetchDescriptor<AdaptationRecord>())
        XCTAssertEqual(records.map(\.kind), [.lighter])
        XCTAssertEqual(records.first?.completedSessions, 2)
        XCTAssertTrue(records.first!.message.hasPrefix("2 of 3 sessions"))
        let week2 = try! context.fetch(FetchDescriptor<PlannedSession>()).filter { $0.week == 2 }
        XCTAssertTrue(week2.allSatisfy { $0.adjustmentNote?.contains("10% shorter") == true })
        XCTAssertTrue(try! context.fetch(FetchDescriptor<PlannedSession>()).filter { $0.week == 3 }.allSatisfy { $0.adjustmentNote == nil })
    }
}

@MainActor
final class RunInsightsTests: XCTestCase {
    private func run(longest: TimeInterval?, duration: TimeInterval = 1800, at offset: TimeInterval = 0) -> Run {
        let start = Date(timeIntervalSince1970: 1_000_000 + offset)
        let segments = longest.map { [RecordedSegment(kind: .run, startedAt: start, endedAt: start + $0, activeDuration: $0)] } ?? []
        return Run(startedAt: start, endedAt: start + duration, activeDuration: duration, distanceMeters: 3000, sessionKind: .intervals, segments: segments)
    }

    private func session(week: Int = 5, minutes: Int = 30, state: CompletionState = .planned) -> PlannedSession {
        let session = PlannedSession(week: week, scheduledAt: .now, kind: .intervals, title: "Run/walk intervals", intervals: [IntervalDefinition(kind: .run, durationSeconds: minutes * 60)])
        session.state = state
        return session
    }

    func testFirstRunIsCelebratedOnce() {
        let notes = RunInsights.notes(for: run(longest: 60), session: nil, previousRuns: [], weekSessions: [], nextSession: nil, isFresh: false)
        XCTAssertEqual(notes.first?.kind, .milestone)
        XCTAssertTrue(notes.first!.text.hasPrefix("First run"))
    }

    func testLongestRunMilestoneOnlyWhenClearlyLonger() {
        let previous = [run(longest: 420)]
        let longer = RunInsights.notes(for: run(longest: 480, at: 100), session: nil, previousRuns: previous, weekSessions: [], nextSession: nil, isFresh: false)
        XCTAssertEqual(longer.first?.text, "Longest continuous run so far: 8:00 (previous best 7:00).")
        let same = RunInsights.notes(for: run(longest: 425, at: 100), session: nil, previousRuns: previous, weekSessions: [], nextSession: nil, isFresh: false)
        XCTAssertTrue(same.allSatisfy { $0.kind != .milestone })
    }

    func testShortRunStillCountsWithoutBlame() {
        let planned = session(minutes: 30, state: .completed)
        let notes = RunInsights.notes(for: run(longest: nil, duration: 20 * 60, at: 100), session: planned, previousRuns: [run(longest: nil)], weekSessions: [planned], nextSession: nil, isFresh: true)
        XCTAssertTrue(notes.contains { $0.text.hasPrefix("20 of 30 minutes — it still counts") })
    }

    func testWeekCompleteAndNextSession() {
        let done = (0..<3).map { _ in session(state: .completed) }
        let next = session(week: 6)
        let previous = done.prefix(2).map { session -> Run in
            let earlier = run(longest: nil)
            earlier.plannedSessionID = session.id
            return earlier
        }
        let notes = RunInsights.notes(for: run(longest: nil, at: 100), session: done[2], previousRuns: previous, weekSessions: done, nextSession: next, isFresh: true)
        XCTAssertTrue(notes.contains { $0.text.hasPrefix("Week 5 complete: 3 of 3 sessions") })
        XCTAssertTrue(notes.contains { $0.text.hasPrefix("Next:") })
        let history = RunInsights.notes(for: run(longest: nil, at: 100), session: done[2], previousRuns: previous, weekSessions: done, nextSession: next, isFresh: false)
        XCTAssertFalse(history.contains { $0.text.hasPrefix("Next:") })
    }

    func testWeekProgressIsAsOfThatRun() {
        let week = (0..<3).map { _ in session(state: .completed) }
        let earlier = run(longest: nil)
        earlier.plannedSessionID = week[0].id
        // Viewing session 2 later, after session 3 was also done: still "2 of 3".
        let notes = RunInsights.notes(for: run(longest: nil, at: 100), session: week[1], previousRuns: [earlier], weekSessions: week, nextSession: nil, isFresh: false)
        XCTAssertTrue(notes.contains { $0.text == "Session 2 of 3 in week 5." })
    }
}

// MARK: - Run cues

@MainActor
final class RunCueTimingTests: XCTestCase {
    func testHalfwaySnapsToNearbySwitch() {
        // 5:00 warm-up, 8 × (1:00 run + 1:30 walk), 5:00 cool-down = 30:00 total.
        let intervals = [
            IntervalDefinition(kind: .warmup, durationSeconds: 300),
            IntervalDefinition(kind: .run, durationSeconds: 60, repeatCount: 8),
            IntervalDefinition(kind: .walk, durationSeconds: 90, repeatCount: 8),
            IntervalDefinition(kind: .cooldown, durationSeconds: 300),
        ]
        var total: TimeInterval = 0
        let ends = intervals.timeline.map { total += TimeInterval($0.durationSeconds); return total }
        let mark = RunSessionController.halfwayMark(intervalEnds: ends)
        XCTAssertNotNil(mark)
        XCTAssertTrue(ends.contains(mark!), "midpoint near a switch should land on it")
        XCTAssertEqual(mark!, total / 2, accuracy: 15)
    }

    func testHalfwayInsideLongIntervalStaysAtMidpoint() {
        let ends: [TimeInterval] = [300, 1500, 1800]
        XCTAssertEqual(RunSessionController.halfwayMark(intervalEnds: ends), 900)
    }

    func testNoHalfwayForVeryShortSession() {
        XCTAssertNil(RunSessionController.halfwayMark(intervalEnds: [60, 180]))
    }

    func testMinutesLeftBoundaries() {
        XCTAssertEqual(RunSessionController.minutesLeft(300), 5)
        XCTAssertEqual(RunSessionController.minutesLeft(240.2), 5)
        XCTAssertEqual(RunSessionController.minutesLeft(240), 4)
        XCTAssertEqual(RunSessionController.minutesLeft(181), 4)
        XCTAssertEqual(RunSessionController.minutesLeft(59), 1)
    }

    func testHalfwayPhraseRoundsToHalfMinute() {
        XCTAssertEqual(SoundCueService.halfwayPhrase(remainingSeconds: 757), "Halfway there, 12 and a half minutes to go.")
        XCTAssertEqual(SoundCueService.halfwayPhrase(remainingSeconds: 900), "Halfway there, 15 minutes to go.")
    }
}
