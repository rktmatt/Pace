import Foundation

/// Turns a permitted Adaptation into concrete edits on PlannedSession rows.
/// Only ever moves sessions, repeats the current week's prescription, or reduces
/// run segments — never invents new session types or increases volume beyond
/// what the program already prescribed.
enum AdaptationApplier {
    /// Returns sessions newly created by the adaptation (only `repeatCurrentWeek`
    /// creates any); the caller inserts them into its model context.
    @discardableResult
    static func apply(_ adaptation: Adaptation, currentWeek: Int, to sessions: [PlannedSession], today: Date = .now, calendar: Calendar = .current) -> [PlannedSession] {
        switch adaptation {
        case .unchanged, .holdProgression:
            return []

        case .repeatCurrentWeek:
            return repeatWeek(currentWeek, sessions: sessions, today: today, calendar: calendar)

        case .reduceNextWeek(let fraction):
            let targetWeek = currentWeek + 1
            let nextWeek = sessions.filter { (session: PlannedSession) -> Bool in
                session.week == targetWeek && session.state == .planned
            }
            for session in nextWeek {
                session.intervals = session.intervals.map { interval in
                    guard interval.kind == .run else { return interval }
                    var reduced = interval
                    reduced.durationSeconds = Int(Double(interval.durationSeconds) * (1 - fraction))
                    return reduced
                }
            }
            return []

        case .alignSchedule(let weekdays):
            guard !weekdays.isEmpty else { return [] }
            let filtered = sessions.filter { (session: PlannedSession) -> Bool in
                session.week > currentWeek && session.state == .planned
            }
            let upcoming = filtered.sorted { $0.scheduledAt < $1.scheduledAt }
            for (index, session) in upcoming.enumerated() {
                let targetWeekday = weekdays[index % weekdays.count]
                let weekStart = calendar.startOfISOWeek(for: session.scheduledAt)
                session.scheduledAt = calendar.date(byAdding: .day, value: targetWeekday - 1, to: weekStart) ?? session.scheduledAt
            }
            return []
        }
    }

    /// Schedules a fresh copy of the current week's sessions and pushes every
    /// later week back by the same amount. The copy lands in the week after the
    /// original — or this week, if the runner has been away longer than that —
    /// so a long break doesn't leave a backlog of past-due sessions.
    private static func repeatWeek(_ week: Int, sessions: [PlannedSession], today: Date, calendar: Calendar) -> [PlannedSession] {
        let block = TrainingAnalyzer.currentBlock(week: week, of: sessions, calendar: calendar)
        guard let latest = block.map(\.scheduledAt).max() else { return [] }

        let blockStart = calendar.startOfISOWeek(for: latest)
        let followingWeek = calendar.date(byAdding: .day, value: 7, to: blockStart) ?? blockStart
        let target = max(followingWeek, calendar.startOfISOWeek(for: today))
        let offsetDays = calendar.dateComponents([.day], from: blockStart, to: target).day ?? 7

        func shifted(_ date: Date) -> Date {
            calendar.date(byAdding: .day, value: offsetDays, to: date) ?? date
        }

        for session in sessions where session.week > week {
            session.scheduledAt = shifted(session.scheduledAt)
        }
        return block.sorted { $0.scheduledAt < $1.scheduledAt }.map { original in
            PlannedSession(week: week, scheduledAt: shifted(original.scheduledAt), kind: original.kind, title: original.title, intervals: original.intervals)
        }
    }
}
