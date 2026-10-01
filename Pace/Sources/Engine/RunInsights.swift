import Foundation

/// One line on the run recap.
struct RunInsight: Identifiable, Equatable {
    enum Kind { case milestone, progress, info }

    let kind: Kind
    let symbol: String
    let text: String
    var id: String { text }
}

/// The recap's short notes, derived only from recorded data — real milestones,
/// where the week stands, what's next. Same tone as `AdaptationEngine`:
/// consistency over performance, a shorter run still counts, nothing is owed.
/// It never changes the plan; adaptation stays weekly so one bad day isn't
/// over-read.
enum RunInsights {
    /// Below this, a "longest run" isn't worth calling out.
    private static let milestoneFloor: TimeInterval = 60
    /// Run segments are timed to the second; ignore jitter when comparing bests.
    private static let milestoneMargin: TimeInterval = 15

    /// - Parameters:
    ///   - previousRuns: every run recorded before this one.
    ///   - weekSessions: the current attempt at this session's program week.
    ///   - nextSession: the next planned session, if any.
    ///   - isFresh: true right after the run. Only "what's next" depends on it;
    ///     every other note is computed as of this run, so History shows it too.
    static func notes(for run: Run, session: PlannedSession?, previousRuns: [Run], weekSessions: [PlannedSession], nextSession: PlannedSession?, isFresh: Bool) -> [RunInsight] {
        var notes: [RunInsight] = []

        if previousRuns.isEmpty {
            notes.append(.init(kind: .milestone, symbol: "flag.fill", text: "First run recorded. Starting is the hardest part, and it's done."))
        } else if let milestone = longestRunMilestone(run, previousRuns: previousRuns) {
            notes.append(milestone)
        }

        if let session {
            let planned = TimeInterval(session.plannedDurationSeconds)
            if planned > 0, run.duration < planned * 0.9 {
                notes.append(.init(kind: .info, symbol: "checkmark.circle", text: "\(Int(run.duration / 60)) of \(Int(planned / 60)) minutes — it still counts as a session. Stopping when you need to is part of training."))
            }
        }

        if let session {
            // As of this run: sessions of the week completed by it or by an earlier run.
            let runIDs = Set(previousRuns.compactMap(\.plannedSessionID))
            let done = weekSessions.filter { $0.state == .completed && ($0.id == session.id || runIDs.contains($0.id)) }.count
            let total = weekSessions.count
            if total > 0 {
                let text = done >= total
                    ? "Week \(session.week) complete: \(done) of \(total) sessions. That consistency is what builds a runner."
                    : "Session \(done) of \(total) in week \(session.week)."
                notes.append(.init(kind: .progress, symbol: "calendar", text: text))
            }
        } else {
            notes.append(.init(kind: .info, symbol: "stopwatch", text: "Free runs are extra time on your feet. Your plan stays as it is."))
        }

        if isFresh, let nextSession {
            let day = nextSession.scheduledAt.formatted(.dateTime.weekday(.wide))
            notes.append(.init(kind: .info, symbol: "arrow.right.circle", text: "Next: \(day), \(nextSession.title.lowercased()), \(nextSession.plannedDurationSeconds / 60) min."))
        }
        return notes
    }

    private static func longestRunMilestone(_ run: Run, previousRuns: [Run]) -> RunInsight? {
        guard let longest = longestRun(in: run), longest >= milestoneFloor else { return nil }
        // Runs recorded before segments existed can't be compared; only claim a
        // best against runs that have them.
        let previous = previousRuns.compactMap(longestRun(in:))
        guard let best = previous.max(), longest > best + milestoneMargin else { return nil }
        return .init(kind: .milestone, symbol: "trophy.fill", text: "Longest continuous run so far: \(Format.clock(longest)) (previous best \(Format.clock(best))).")
    }

    private static func longestRun(in run: Run) -> TimeInterval? {
        run.segments?.filter { $0.kind == .run }.map(\.activeDuration).max()
    }
}
