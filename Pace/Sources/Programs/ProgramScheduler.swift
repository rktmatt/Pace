import Foundation

/// Turns a static ProgramDefinition into concrete, dated PlannedSession rows.
/// Runs when a program is started (or restarted at a chosen week); AdaptationEngine
/// reschedules individual sessions afterward — the definition itself is never mutated.
enum ProgramScheduler {
    /// Schedules `firstWeek` onward, with `firstWeek` landing in the week containing `startDate`.
    static func plannedSessions(for definition: ProgramDefinition, startingFrom startDate: Date, firstWeek: Int = 1, calendar: Calendar = .current) -> [PlannedSession] {
        let mondayOfStartWeek = mostRecentMonday(onOrBefore: startDate, calendar: calendar)

        return definition.weeks.filter { $0.weekNumber >= firstWeek }.flatMap { week -> [PlannedSession] in
            let weekStart = calendar.date(byAdding: .day, value: (week.weekNumber - firstWeek) * 7, to: mondayOfStartWeek) ?? mondayOfStartWeek
            return week.sessions.map { session in
                let dayOffset = session.suggestedWeekday - 1
                let scheduledAt = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) ?? weekStart
                return PlannedSession(
                    week: week.weekNumber,
                    scheduledAt: scheduledAt,
                    kind: session.kind,
                    title: session.title,
                    intervals: session.intervals
                )
            }
        }
    }

    private static func mostRecentMonday(onOrBefore date: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: date) // Sunday = 1 ... Saturday = 7
        let isoWeekday = weekday == 1 ? 7 : weekday - 1 // Monday = 1 ... Sunday = 7
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -(isoWeekday - 1), to: startOfDay) ?? startOfDay
    }
}
