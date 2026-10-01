import Foundation
import SwiftData

/// Builds the deterministic TrainingSnapshot that feeds AdaptationEngine,
/// purely from what actually happened — no inference, no guessing at causes.
enum TrainingAnalyzer {
    static func snapshot(week: Int, plannedSessions: [PlannedSession], runs: [Run], calendar: Calendar = .current) -> TrainingSnapshot {
        let sessionsInWeek = currentBlock(week: week, of: plannedSessions, calendar: calendar)
        let sessionIDsInWeek = Set(sessionsInWeek.map(\.id))
        let runsForWeek = runs.filter { run in
            guard let plannedSessionID = run.plannedSessionID else { return false }
            return sessionIDsInWeek.contains(plannedSessionID)
        }

        let completed = sessionsInWeek.filter { $0.state == .completed }.count
        let plannedMinutes = sessionsInWeek.reduce(0) { $0 + $1.plannedDurationSeconds / 60 }
        let actualMinutes = Int(runsForWeek.reduce(0.0) { $0 + $1.duration } / 60)

        return TrainingSnapshot(
            plannedSessions: sessionsInWeek.count,
            completedSessions: completed,
            plannedMinutes: plannedMinutes,
            actualMinutes: actualMinutes,
            actualWeekdays: runsForWeek.map { calendar.isoWeekday(of: $0.startedAt) },
            scheduledWeekdays: sessionsInWeek.map { calendar.isoWeekday(of: $0.scheduledAt) }
        )
    }

    /// The sessions making up the latest attempt at a program week. Normally
    /// that's every session with that week number, but when a week is repeated
    /// the earlier attempt keeps its number — only the newest calendar week counts.
    static func currentBlock(week: Int, of sessions: [PlannedSession], calendar: Calendar = .current) -> [PlannedSession] {
        let inWeek = sessions.filter { $0.week == week }
        guard let latest = inWeek.map(\.scheduledAt).max() else { return [] }
        let blockStart = calendar.startOfISOWeek(for: latest)
        return inWeek.filter { $0.scheduledAt >= blockStart }
    }
}

extension Calendar {
    /// Monday = 1 ... Sunday = 7, regardless of the locale's first weekday.
    func isoWeekday(of date: Date) -> Int {
        let weekday = component(.weekday, from: date) // Sunday = 1 ... Saturday = 7
        return weekday == 1 ? 7 : weekday - 1
    }

    /// Midnight on the Monday of the week containing `date`.
    func startOfISOWeek(for date: Date) -> Date {
        let day = startOfDay(for: date)
        return self.date(byAdding: .day, value: -(isoWeekday(of: date) - 1), to: day) ?? day
    }
}
