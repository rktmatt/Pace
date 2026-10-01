import Foundation
import SwiftData

/// Orchestrates the seed-once program, day-to-day session lookup, and the
/// weekly adaptation check. This is the only place that ties the deterministic
/// engine to real persisted state.
@MainActor
struct ProgramCoordinator {
    let context: ModelContext
    let calendar: Calendar = .current

    func ensureProgramSeeded() {
        let existing = try? context.fetch(FetchDescriptor<ActiveProgram>())
        guard existing?.isEmpty ?? true else { return }

        let definition = Couch5KProgram.definition
        let program = ActiveProgram(definitionID: definition.id)
        program.programVersion = Couch5KProgram.version
        context.insert(program)

        for session in ProgramScheduler.plannedSessions(for: definition, startingFrom: .now, calendar: calendar) {
            context.insert(session)
        }
    }

    /// Restarts the program at `week` — for runners arriving from another plan,
    /// or going back after time off. Upcoming and missed sessions are replaced;
    /// completed sessions stay so run history keeps its titles.
    func restartProgram(atWeek week: Int, today: Date = .now) {
        let definition = Couch5KProgram.definition
        let week = min(max(week, 1), definition.totalWeeks)
        let schedule = restartSchedule(atWeek: week, today: today)

        let sessions = (try? context.fetch(FetchDescriptor<PlannedSession>())) ?? []
        for session in sessions where session.state != .completed {
            context.delete(session)
        }
        schedule.forEach(context.insert)

        let program = activeProgram() ?? {
            let program = ActiveProgram(definitionID: definition.id)
            context.insert(program)
            return program
        }()
        program.currentWeek = week
        program.programVersion = Couch5KProgram.version
        let message = "Starting at week \(week). Your completed runs stay in History; the plan picks up from here."
        program.lastFeedback = message
        context.insert(AdaptationRecord(date: today, week: week, kind: .restarted, message: message))
    }

    /// When the bundled program content changes, rebuilds every session not yet
    /// run from the new definition — same dates, same week, matched by position
    /// within its calendar week. Completed and skipped sessions keep what was
    /// actually prescribed. Earlier adaptations to upcoming sessions are dropped
    /// (the new content is at most as demanding), and the Home banner says so.
    func migrateToCurrentProgramVersion() {
        guard let program = activeProgram(), program.programVersion < Couch5KProgram.version else { return }
        let weeks = Dictionary(uniqueKeysWithValues: Couch5KProgram.definition.weeks.map { ($0.weekNumber, $0) })
        let sessions = (try? context.fetch(FetchDescriptor<PlannedSession>())) ?? []
        let blocks = Dictionary(grouping: sessions) { BlockKey(week: $0.week, start: calendar.startOfISOWeek(for: $0.scheduledAt)) }

        for (key, block) in blocks {
            guard let definitions = weeks[key.week]?.sessions, !definitions.isEmpty else { continue }
            for (index, session) in block.sorted(by: { $0.scheduledAt < $1.scheduledAt }).enumerated() where session.state == .planned {
                let definition = definitions[min(index, definitions.count - 1)]
                session.title = definition.title
                session.kindRaw = definition.kind.rawValue
                session.intervals = definition.intervals
            }
        }
        program.programVersion = Couch5KProgram.version
        let message = "The program has been updated: runs now build up in smaller steps from one session to the next, with no big jump to continuous running. Your schedule and completed runs are unchanged."
        program.lastFeedback = message
        context.insert(AdaptationRecord(week: program.currentWeek, kind: .programUpdated, message: message))
    }

    private struct BlockKey: Hashable {
        let week: Int
        let start: Date
    }

    /// The sessions a restart at `week` would create (not inserted). The week
    /// starts now: sessions whose suggested day has already passed move onto
    /// the days left this week, in order, one per day. It slips to next Monday
    /// only when the rest of the week can't hold every session, or when this
    /// calendar week already has completed sessions of the same program week
    /// (they would merge into one block).
    func restartSchedule(atWeek week: Int, today: Date = .now) -> [PlannedSession] {
        let definition = Couch5KProgram.definition
        let thisMonday = calendar.startOfISOWeek(for: today)
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: thisMonday) ?? thisMonday

        let runs = (try? context.fetch(FetchDescriptor<Run>())) ?? []
        let ranToday = runs.contains { calendar.isDate($0.startedAt, inSameDayAs: today) }
        let firstDay = calendar.isoWeekday(of: today) + (ranToday ? 1 : 0)

        let completed = ((try? context.fetch(FetchDescriptor<PlannedSession>())) ?? [])
            .filter { $0.state == .completed && $0.week == week && $0.scheduledAt >= thisMonday }
        let sessionsInWeek = definition.weeks.first { $0.weekNumber == week }?.sessions.count ?? 0
        let fitsThisWeek = completed.isEmpty && firstDay + sessionsInWeek - 1 <= 7

        let sessions = ProgramScheduler.plannedSessions(for: definition, startingFrom: fitsThisWeek ? thisMonday : nextMonday, firstWeek: week, calendar: calendar)
        guard fitsThisWeek else { return sessions }

        let firstWeek = sessions.filter { $0.week == week }.sorted { $0.scheduledAt < $1.scheduledAt }
        for (index, session) in firstWeek.enumerated() {
            // Both sequences increase strictly, so their max does too: no two sessions share a day.
            let day = max(calendar.isoWeekday(of: session.scheduledAt), firstDay + index)
            session.scheduledAt = calendar.date(byAdding: .day, value: day - 1, to: thisMonday) ?? session.scheduledAt
        }
        return sessions
    }

    func activeProgram() -> ActiveProgram? {
        try? context.fetch(FetchDescriptor<ActiveProgram>()).first
    }

    func todaysSession(allSessions: [PlannedSession]) -> PlannedSession? {
        let upcoming = allSessions
            .filter { $0.state == .planned }
            .sorted { $0.scheduledAt < $1.scheduledAt }
        return upcoming.first
    }

    /// The sessions of the program's current week, as shown on Home.
    func currentWeekSessions(program: ActiveProgram, allSessions: [PlannedSession]) -> [PlannedSession] {
        TrainingAnalyzer.currentBlock(week: program.currentWeek, of: allSessions, calendar: calendar)
    }

    /// Runs the weekly check for every week that has fully elapsed — usually
    /// zero or one, but several if the app wasn't opened for a while.
    func evaluateWeeksIfNeeded(program: ActiveProgram) {
        for _ in 0..<Couch5KProgram.definition.totalWeeks * 2 {
            let sessions = (try? context.fetch(FetchDescriptor<PlannedSession>())) ?? []
            let runs = (try? context.fetch(FetchDescriptor<Run>())) ?? []
            guard evaluateWeekIfNeeded(program: program, allSessions: sessions, allRuns: runs) else { break }
        }
        skipSessionsBeforeCurrentWeek(program: program)
    }

    /// Recomputes the deterministic snapshot for the current week and, once
    /// that week's last session has passed, applies a bounded adaptation to
    /// what comes next. Returns whether a week was evaluated.
    @discardableResult
    func evaluateWeekIfNeeded(program: ActiveProgram, allSessions: [PlannedSession], allRuns: [Run]) -> Bool {
        let weekSessions = TrainingAnalyzer.currentBlock(week: program.currentWeek, of: allSessions, calendar: calendar)
        guard let lastScheduled = weekSessions.map(\.scheduledAt).max() else { return false }
        guard calendar.startOfDay(for: .now) > calendar.startOfDay(for: lastScheduled) else { return false }

        let snapshot = TrainingAnalyzer.snapshot(week: program.currentWeek, plannedSessions: allSessions, runs: allRuns, calendar: calendar)
        let decision = AdaptationEngine().decide(for: snapshot)

        // Sessions left undone in an elapsed week are missed, not owed — they
        // must not resurface as "today's session" later.
        for session in weekSessions where session.state == .planned {
            session.state = .skipped
        }
        let datesBefore = Dictionary(uniqueKeysWithValues: allSessions.map { ($0.id, $0.scheduledAt) })
        let created = AdaptationApplier.apply(decision.adaptation, currentWeek: program.currentWeek, to: allSessions, calendar: calendar)
        created.forEach(context.insert)
        annotate(decision.adaptation, week: program.currentWeek, snapshot: snapshot, sessions: allSessions, created: created, datesBefore: datesBefore)

        context.insert(AdaptationRecord(date: lastScheduled, week: program.currentWeek, kind: AdaptationKind(decision.adaptation), snapshot: snapshot, message: decision.explanation))
        program.lastFeedback = decision.explanation
        if decision.adaptation != .repeatCurrentWeek {
            program.currentWeek += 1
        }
        return true
    }

    /// Labels every session an adaptation changed with a short, specific reason,
    /// so the Plan and the run recap can say what changed and why.
    private func annotate(_ adaptation: Adaptation, week: Int, snapshot: TrainingSnapshot, sessions: [PlannedSession], created: [PlannedSession], datesBefore: [UUID: Date]) {
        let numbers = "\(snapshot.completedSessions) of \(snapshot.plannedSessions) sessions in week \(week)"
        switch adaptation {
        case .unchanged, .holdProgression:
            return
        case .repeatCurrentWeek:
            created.forEach { $0.adjustmentNote = "A second go at week \(week) after \(numbers) — picking up right where you are." }
        case .reduceNextWeek(let fraction):
            for session in sessions where session.week == week + 1 && session.state == .planned {
                session.adjustmentNote = "Runs \(Int((fraction * 100).rounded()))% shorter after \(numbers), so the step up stays comfortable."
            }
        case .alignSchedule(let weekdays):
            for session in sessions where session.state == .planned && datesBefore[session.id] != session.scheduledAt {
                session.adjustmentNote = "Moved to match the days you've been running (\(AdaptationEngine.dayNames(weekdays)))."
            }
        }
    }

    /// Repairs state from builds that left earlier weeks' sessions planned.
    private func skipSessionsBeforeCurrentWeek(program: ActiveProgram) {
        let sessions = (try? context.fetch(FetchDescriptor<PlannedSession>())) ?? []
        for session in sessions where session.week < program.currentWeek && session.state == .planned {
            session.state = .skipped
        }
    }

    @discardableResult
    /// Records a finished run. `session` is nil for a free run, which stays
    /// outside the program: it never completes a planned session or feeds the
    /// weekly adaptation check.
    func recordRun(id: UUID = UUID(), startedAt: Date, endedAt: Date, activeDuration: TimeInterval, distanceMeters: Double, routePoints: [RoutePoint], segments: [RecordedSegment] = [], for session: PlannedSession?) -> Run {
        let run = Run(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            activeDuration: activeDuration,
            distanceMeters: distanceMeters,
            sessionKind: session?.kind ?? .free,
            plannedSessionID: session?.id,
            routePoints: routePoints,
            segments: segments
        )
        context.insert(run)
        session?.state = .completed
        return run
    }

    /// Records a run finished on the Watch. Idempotent by run id, since a file
    /// transfer can be delivered again after a relaunch. A run for a session
    /// that has since been completed on the phone is kept as an extra free run,
    /// so the week's minutes aren't counted twice.
    @discardableResult
    func recordWatchRun(_ payload: WatchRun) -> Run? {
        let id = payload.id
        var existing = FetchDescriptor<Run>(predicate: #Predicate { $0.id == id })
        existing.fetchLimit = 1
        guard (try? context.fetch(existing))?.isEmpty ?? true else { return nil }

        var session: PlannedSession?
        if let sessionID = payload.plannedSessionID {
            var descriptor = FetchDescriptor<PlannedSession>(predicate: #Predicate { $0.id == sessionID })
            descriptor.fetchLimit = 1
            session = (try? context.fetch(descriptor))?.first.flatMap { $0.state == .completed ? nil : $0 }
        }
        let run = recordRun(
            id: payload.id,
            startedAt: payload.startedAt,
            endedAt: payload.endedAt,
            activeDuration: payload.activeDuration,
            distanceMeters: payload.distanceMeters,
            routePoints: payload.route.map(RoutePoint.init),
            segments: payload.segments,
            for: session
        )
        run.averageHeartRate = payload.averageHeartRate
        run.maxHeartRate = payload.maxHeartRate
        run.heartRateSamples = payload.heartRate
        return run
    }
}
