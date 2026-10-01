import Foundation

/// A deliberately small policy surface. The evidence-based program is never
/// rewritten — only these bounded moves are permitted, and they only ever
/// hold or reduce load, never increase it beyond plan.
struct TrainingSnapshot {
    let plannedSessions: Int
    let completedSessions: Int
    let plannedMinutes: Int
    let actualMinutes: Int
    let actualWeekdays: [Int]
    let scheduledWeekdays: [Int]
}

enum Adaptation: Equatable {
    case unchanged
    case alignSchedule(toWeekdays: [Int])
    case repeatCurrentWeek
    case reduceNextWeek(by: Double)
    case holdProgression
}

struct AdaptationDecision: Equatable {
    let adaptation: Adaptation
    let explanation: String
}

/// Tone: consistency over performance. Life happens — a missed session is
/// never a failure, nothing is ever "owed", and every message names the
/// actual numbers rather than generic praise or blame.
struct AdaptationEngine {
    /// Conservative rules only. Never use missed volume to increase the next session.
    func decide(for snapshot: TrainingSnapshot) -> AdaptationDecision {
        guard snapshot.plannedSessions > 0 else {
            return .init(adaptation: .unchanged, explanation: "Your next session is ready when you are.")
        }

        let completed = snapshot.completedSessions, planned = snapshot.plannedSessions
        let completion = Double(completed) / Double(planned)
        let volume = Double(snapshot.actualMinutes) / Double(max(snapshot.plannedMinutes, 1))
        let sessions = "\(completed) of \(planned) sessions"

        // Integer comparison: 1 of 3 sessions is exactly a third, which a
        // floating-point `<= 0.33` would miss.
        if completed * 3 <= planned {
            let opening = completed == 0
                ? "No runs this week — life happens, and that's fine."
                : "\(sessions) this week. Busy weeks happen, and nothing is lost."
            return .init(adaptation: .repeatCurrentWeek,
                         explanation: "\(opening) You'll run this week again, picking up right where you are. Coming back is what builds the habit.")
        }
        if volume > 1.25 {
            return .init(adaptation: .holdProgression,
                         explanation: "\(snapshot.actualMinutes) minutes run against \(snapshot.plannedMinutes) planned — plenty of energy this week. Next week stays as written so your body can absorb it. Steady beats more.")
        }
        if completion < 0.67 || volume < 0.67 {
            return .init(adaptation: .reduceNextWeek(by: 0.10),
                         explanation: "\(sessions), \(snapshot.actualMinutes) of \(snapshot.plannedMinutes) minutes — a real week of training around real life. Next week's runs are slightly shorter so the step up stays comfortable. Nothing to make up.")
        }
        if shouldAlignDays(snapshot) {
            let days = stableDays(snapshot.actualWeekdays)
            return .init(adaptation: .alignSchedule(toWeekdays: days),
                         explanation: "\(sessions), on your own days. The schedule now follows the days you actually run: \(Self.dayNames(days)).")
        }
        return .init(adaptation: .unchanged,
                     explanation: "\(sessions) done. That kind of consistency is exactly what moves you forward. Next week continues as planned.")
    }

    /// [2, 4, 6] → "Tue, Thu and Sat".
    static func dayNames(_ isoWeekdays: [Int]) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols // Sunday first
        let names = isoWeekdays.map { symbols[$0 % 7] }
        return ListFormatter.localizedString(byJoining: names)
    }

    private func shouldAlignDays(_ snapshot: TrainingSnapshot) -> Bool {
        let actual = stableDays(snapshot.actualWeekdays)
        return actual.count >= 2 && actual != stableDays(snapshot.scheduledWeekdays)
    }

    private func stableDays(_ days: [Int]) -> [Int] {
        Array(Set(days)).sorted()
    }
}
