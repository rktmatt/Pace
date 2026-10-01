import Foundation

/// A 9-week run/walk beginner-to-5K program.
///
/// Built on the "Couch to 5K" run/walk model (NHS programme, Galloway's
/// run-walk-run method), with the progression shaped by what the injury
/// literature actually supports:
/// - Single-session spikes matter more than weekly totals. In a 5,200-runner
///   cohort, a session >10% longer than the longest run of the previous 30 days
///   raised injury risk, while weekly load ratios did not (Frandsen et al. 2025).
///   So progression here is defined per session: the longest continuous run
///   grows by at most ~20% (or 2 minutes while bouts are still short) from one
///   session to the next — never the 10 → 25 minute jump many C25K plans make.
/// - Each week opens at roughly the previous week's level and steps up within
///   the week, so every new peak is a small step from a recent one.
/// - Running time per session also grows gradually (≤ ~25% session to session),
///   while total session length stays 30–40 minutes: running replaces walking
///   rather than piling on time. Novices who increased weekly distance by >30%
///   had more injuries (Nielsen et al. 2014); a slower 10%-per-week schedule
///   didn't reduce injuries further (Buist et al. 2008), so 9 weeks is kept.
/// - Three sessions a week (Mon / Wed / Fri) with a rest day between.
///
/// `ProgramTests` enforces the session-to-session limits above.
enum Couch5KProgram {
    /// Bump when the session content changes, so already-scheduled sessions
    /// are rebuilt from the new definition.
    /// 2: per-session progression rewrite (no 10 → 25 min jump in weeks 6–7).
    /// 3: week 6 opens with three runs and 1-minute walks instead of 2 × 8 min.
    static let version = 3

    static let definition: ProgramDefinition = {
        let weekdays = [1, 3, 5] // Mon / Wed / Fri, with rest between

        func run(_ minutes: Double) -> IntervalDefinition {
            IntervalDefinition(kind: .run, durationSeconds: Int(minutes * 60))
        }
        func walk(_ minutes: Double) -> IntervalDefinition {
            IntervalDefinition(kind: .walk, durationSeconds: Int(minutes * 60))
        }

        /// Every session opens with a 5-minute brisk walk and closes with a 5-minute easy walk.
        func session(_ day: Int, _ title: String, _ main: [IntervalDefinition]) -> SessionDefinition {
            let isContinuous = main.count == 1
            return SessionDefinition(
                suggestedWeekday: weekdays[day],
                kind: isContinuous ? .easy : .intervals,
                title: title,
                intervals: [IntervalDefinition(kind: .warmup, durationSeconds: 300)]
                    + main
                    + [IntervalDefinition(kind: .cooldown, durationSeconds: 300)]
            )
        }

        /// `repeats` × (run, walk) — the same session on all three days.
        func repeatsWeek(_ number: Int, repeats: Int, run runMinutes: Double, walk walkMinutes: Double) -> WeekDefinition {
            let main = [
                IntervalDefinition(kind: .run, durationSeconds: Int(runMinutes * 60), repeatCount: repeats),
                IntervalDefinition(kind: .walk, durationSeconds: Int(walkMinutes * 60), repeatCount: repeats),
            ]
            return WeekDefinition(weekNumber: number, sessions: (0..<3).map { session($0, "Run/walk intervals", main) })
        }

        let baseBuilding = PhaseDefinition(
            name: "Base building",
            rationale: "Short runs alternated with walking let joints, tendons and bone adapt before they carry continuous running load. Each session is about 30 minutes; only the share spent running changes.",
            weeks: [
                repeatsWeek(1, repeats: 8, run: 1, walk: 1.5),   // 8 min running, longest 1:00
                repeatsWeek(2, repeats: 6, run: 1.5, walk: 2),   // 9 min, longest 1:30
                repeatsWeek(3, repeats: 5, run: 2, walk: 1.5),   // 10 min, longest 2:00
                repeatsWeek(4, repeats: 4, run: 3, walk: 1.5),   // 12 min, longest 3:00
            ]
        )

        let progression = PhaseDefinition(
            name: "Progression",
            rationale: "Runs get longer and walk breaks fewer. Each week starts close to where the last one ended and builds across its three sessions, so no single run is a big jump from your recent longest.",
            weeks: [
                WeekDefinition(weekNumber: 5, sessions: [
                    session(0, "Run/walk intervals", [
                        IntervalDefinition(kind: .run, durationSeconds: 240, repeatCount: 3),
                        IntervalDefinition(kind: .walk, durationSeconds: 90, repeatCount: 3),
                    ]),                                                                          // 12 min, longest 4:00
                    session(1, "Run/walk intervals", [
                        IntervalDefinition(kind: .run, durationSeconds: 300, repeatCount: 3),
                        IntervalDefinition(kind: .walk, durationSeconds: 120, repeatCount: 3),
                    ]),                                                                          // 15 min, longest 5:00
                    session(2, "Run/walk pyramid", [run(5), walk(1.5), run(6), walk(1.5), run(5)]), // 16 min, longest 6:00
                ]),
                WeekDefinition(weekNumber: 6, sessions: [
                    // Three runs with short walks first, so the longest run grows a
                    // minute at a time (6 → 7 → 8) before the two-run session.
                    session(0, "Run/walk intervals", [run(6), walk(1), run(7), walk(1), run(6)]),  // 19 min, longest 7:00
                    session(1, "Run/walk intervals", [run(7), walk(1), run(8), walk(1), run(7)]),  // 22 min, longest 8:00
                    session(2, "Two long runs", [run(10), walk(2), run(10)]),                     // 20 min, longest 10:00
                ]),
                WeekDefinition(weekNumber: 7, sessions: [
                    session(0, "Long run + short run", [run(12), walk(2), run(8)]),  // 20 min, longest 12:00
                    session(1, "Long run + short run", [run(14), walk(2), run(8)]),  // 22 min, longest 14:00
                    session(2, "Long run + short run", [run(16), walk(2), run(6)]),  // 22 min, longest 16:00
                ]),
            ]
        )

        let toFiveK = PhaseDefinition(
            name: "To 5K",
            rationale: "The last walk break goes. Continuous running time keeps climbing in small steps until you run 30 minutes without stopping — around 5 km for most new runners.",
            weeks: [
                WeekDefinition(weekNumber: 8, sessions: [
                    session(0, "Long run + short run", [run(18), walk(2), run(6)]),  // 24 min, longest 18:00
                    session(1, "Long run + short run", [run(20), walk(2), run(5)]),  // 25 min, longest 20:00
                    session(2, "Continuous run", [run(23)]),                          // 23 min continuous
                ]),
                WeekDefinition(weekNumber: 9, sessions: [
                    session(0, "Continuous run", [run(25)]),
                    session(1, "Continuous run", [run(28)]),
                    session(2, "5K run", [run(30)]),
                ]),
            ]
        )

        return ProgramDefinition(
            id: "couch-to-5k",
            title: "Couch to 5K",
            summary: "A 9-week run/walk progression for beginners, taking you from no running background to 30 minutes of continuous running.",
            phases: [baseBuilding, progression, toFiveK],
            references: [
                "NHS Couch to 5K programme (nhs.uk/live-well/exercise)",
                "Galloway, J. — Run-Walk-Run method",
                "Frandsen et al. (2025), Br J Sports Med — single-session spikes and running injuries in 5,200 runners",
                "Nielsen et al. (2014), J Orthop Sports Phys Ther — weekly distance progression and injury in novice runners",
                "Buist et al. (2008), Am J Sports Med — graded training program for novice runners (RCT)",
            ]
        )
    }()
}
