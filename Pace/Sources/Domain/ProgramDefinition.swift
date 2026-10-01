import Foundation

enum SessionKind: String, Codable, CaseIterable {
    case easy, intervals, recovery, longRun
    /// Unplanned, self-paced run/walk recorded outside the program.
    case free

    var label: String {
        switch self {
        case .easy: "Easy run"
        case .intervals: "Intervals"
        case .recovery: "Recovery run"
        case .longRun: "Long run"
        case .free: "Free run"
        }
    }
}

enum IntervalKind: String, Codable {
    case warmup, run, walk, cooldown

    var voicePrompt: String {
        switch self {
        case .warmup: "Warm up"
        case .run: "Run"
        case .walk: "Walk"
        case .cooldown: "Cool down"
        }
    }
}

/// One block inside a session, e.g. "run 3 minutes" or "walk 90 seconds".
struct IntervalDefinition: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var kind: IntervalKind
    var durationSeconds: Int
    var repeatCount: Int = 1
}

extension Array where Element == IntervalDefinition {
    /// Consecutive intervals sharing the same `repeatCount` form one repeated
    /// block: `[run 1:00 ×8, walk 1:30 ×8]` means "run, walk" eight times — not
    /// eight runs followed by eight walks.
    var repeatBlocks: [(repeatCount: Int, intervals: [IntervalDefinition])] {
        var blocks: [(repeatCount: Int, intervals: [IntervalDefinition])] = []
        for interval in self {
            let count = Swift.max(interval.repeatCount, 1)
            if count > 1, let last = blocks.last, last.repeatCount == count {
                blocks[blocks.count - 1].intervals.append(interval)
            } else {
                blocks.append((count, [interval]))
            }
        }
        return blocks
    }

    /// The longest single run segment, in seconds.
    var longestRunSeconds: Int {
        filter { $0.kind == .run }.map(\.durationSeconds).max() ?? 0
    }

    /// Total time spent running, in seconds.
    var runningSeconds: Int {
        filter { $0.kind == .run }.reduce(0) { $0 + $1.durationSeconds * Swift.max($1.repeatCount, 1) }
    }

    /// The flat, second-by-second order a runner actually performs the intervals in.
    var timeline: [IntervalDefinition] {
        repeatBlocks.flatMap { block in
            (0..<block.repeatCount).flatMap { _ in
                block.intervals.map { IntervalDefinition(kind: $0.kind, durationSeconds: $0.durationSeconds) }
            }
        }
    }
}

/// A single planned workout, expressed as a sequence of intervals.
struct SessionDefinition: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    /// 1 = Monday ... 7 = Sunday. Suggested, not mandatory — the schedule adapts to the user.
    var suggestedWeekday: Int
    var kind: SessionKind
    var title: String
    var intervals: [IntervalDefinition]

    var totalDurationSeconds: Int {
        intervals.reduce(0) { $0 + $1.durationSeconds * $1.repeatCount }
    }
}

/// A week within a phase. Weeks are the unit progressive overload is applied to.
struct WeekDefinition: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var weekNumber: Int
    var isDeload: Bool = false
    var sessions: [SessionDefinition]
}

/// A named block of weeks sharing a training emphasis (base building, progression, taper...).
struct PhaseDefinition: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var rationale: String
    var weeks: [WeekDefinition]
}

/// A complete, hard-coded, evidence-based training program bundled with the app.
/// Structured data — never generated on the fly by a model.
struct ProgramDefinition: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var summary: String
    var phases: [PhaseDefinition]
    var references: [String]

    var weeks: [WeekDefinition] { phases.flatMap(\.weeks) }
    var totalWeeks: Int { weeks.count }
}
