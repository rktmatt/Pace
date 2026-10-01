# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Product vision

This is a small, exceptionally polished running app, primarily for personal use, with the possibility of
publishing to the App Store. Edit this section freely as the vision evolves — treat it as the source of
truth future work should be checked against.

**Philosophy**: evidence-based training, adapted to real life, private by default. The user is not failing
the program — the program adapts to the user. People have jobs, families, travel, bad weeks, and
fluctuating motivation; the goal is sustainable progress, not perfect adherence to a rigid plan.

**Privacy first**
- No account, no backend, no ads, no tracking SDK, no analytics, no developer-operated user database.
- All data lives locally (SwiftData / SQLite-backed). iCloud sync is optional and syncs only what's
  needed, never raw GPS tracks by default.
- The app must be fully functional offline.

**Training programs are structured data, not generated**
- Programs are hard-coded, evidence-based (progressive overload, gradual volume progression, run/walk
  beginner progression, deload weeks), structured as `Program → phases → weeks → sessions → intervals`.
- An LLM may assist with research/wording but is never the source of truth for exercise science, and
  never invents a program's structure at runtime.

**Adaptive training is the core differentiator**
- Flow: evidence-based program → user's actual life (training history) → deterministic analysis →
  permitted adaptations → optional on-device AI phrasing → human explanation.
- The deterministic engine decides *what* can change; permitted adaptations are narrow and conservative:
  move a session, repeat the current week, slightly reduce next week's volume, hold progression, align
  the schedule to days the user actually trains, explain deviations. It must never silently increase
  planned volume beyond what the program prescribes, and never invent new session types.
- Feedback is specific and grounded in the user's actual data, never generic ("you missed sessions" +
  what we changed, not "you failed, try harder"). No guilt, no gamification for its own sake, no fake
  enthusiasm, no AI-as-a-feature branding — AI is an implementation detail that shows up only as
  contextual coaching text, never a chat interface.

**Visual design**: bold, high-contrast, confident — large numerals, strong typography, dark UI, mint
accent, minimal decoration. Not a pastel wellness app. Should be legible and usable mid-run with minimal
attention (see `ActiveRunView`).

**Not yet built / deliberately deferred**: CloudKit sync, Apple Health integration, on-device LLM
narrative phrasing layer (the deterministic engine already produces explanation text in
`AdaptationEngine.decide`; swapping in model-generated phrasing is an isolated follow-up, not a
prerequisite). Keep these out of scope unless explicitly asked for.

## Commands

This is a native Xcode project (SwiftUI + SwiftData), no package manager, no separate lint/test tooling
configured yet.

Build for the simulator:
```bash
xcodebuild -project Pace.xcodeproj -scheme Pace -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

List available simulators if the named device above isn't present:
```bash
xcrun simctl list devices available
```

Install and launch on a booted simulator:
```bash
xcrun simctl install "iPhone 17 Pro" <path-to-Pace.app-in-DerivedData>
xcrun simctl launch "iPhone 17 Pro" com.matthieuroussel.Pace
```

Run unit tests (`PaceTests` target, XCTest, hosted in the app; covers `AdaptationEngine`,
`AdaptationApplier`, `TrainingAnalyzer`, interval expansion and the weekly-evaluation flow):
```bash
xcodebuild test -project Pace.xcodeproj -scheme Pace -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
Add tests there when changing adaptation policy or scheduling logic.

The project file (`Pace.xcodeproj`) was generated with the `xcodeproj` Ruby gem rather than Xcode's GUI or
XcodeGen. If you need to add/remove/move Swift files, either edit `project.pbxproj` directly, regenerate
it with a small Ruby script using `xcodeproj`, or open the project in Xcode and let it manage the file
references — any of these is fine, just keep the group structure under `Pace/Sources` matching the
on-disk folders below.

The app icon is generated, not drawn by hand: `swift scripts/make_app_icon.swift
Pace/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

## Architecture

Source lives under `Pace/Sources`, grouped by role rather than by screen:

- **`Domain/`** — data model, in two layers that must not be conflated:
  - `ProgramDefinition.swift`: static, `Codable` value types describing a training program
    (`ProgramDefinition → PhaseDefinition → WeekDefinition → SessionDefinition → IntervalDefinition`).
    These are bundled content, not user data.
  - `PersistedModels.swift`: SwiftData `@Model` classes for actual user state — `ActiveProgram` (which
    program + current week), `PlannedSession` (a dated, mutable occurrence of a `SessionDefinition`,
    including its own copy of `[IntervalDefinition]` so adaptation can edit it independently of the
    original definition), `Run`, `RoutePoint`.
- **`Programs/`** — bundled program content and scheduling:
  - `Couch5KProgram.swift`: the one hard-coded program (9-week run/walk-to-5K), built with rationale
    comments and literature references. Progression is defined per session (longest continuous run
    ≤ ~20% / +2 min over the previous peak, running time ≤ ~25%), enforced by `ProgramTests`. When session
    content changes, bump `Couch5KProgram.version`: `ProgramCoordinator.migrateToCurrentProgramVersion`
    then rebuilds not-yet-run sessions in place (same dates) on next launch. New programs should follow this same pattern — static data with
    a documented rationale, not procedurally generated.
  - `ProgramScheduler.swift`: turns a `ProgramDefinition` into dated `PlannedSession` rows when a program
    starts, or when the user restarts it at a chosen week (`ProgramCoordinator.restartProgram(atWeek:)`,
    which replaces non-completed sessions and keeps completed ones for history). Otherwise it does not
    run again — subsequent changes go through `AdaptationApplier`.
- **`Engine/`** — the deterministic adaptation pipeline, deliberately separated from persistence and UI:
  - `AdaptationEngine.swift`: pure function `TrainingSnapshot → AdaptationDecision`. No I/O, no SwiftData.
    This is the one place that encodes the adaptation *policy* and is the most important file to keep
    conservative and well-tested as the product evolves.
  - `TrainingAnalyzer.swift`: builds a `TrainingSnapshot` from real `PlannedSession`/`Run` data for a
    given week — the only place "what actually happened" is computed.
  - `AdaptationApplier.swift`: takes an `Adaptation` enum case and mutates `PlannedSession` rows
    (reschedule, shorten run intervals, etc.) accordingly.
  - `RunInsights.swift`: pure rules for the run recap's notes (real milestones like a new longest
    continuous run, "it still counts" for a shortened session, week progress, what's next). Never
    changes the plan — adaptation stays weekly.
  - Every weekly check, restart and program update is saved as an `AdaptationRecord` (shown as the
    "Your weeks" timeline on the Plan tab); sessions an adaptation changed carry `adjustmentNote`,
    shown on the Plan and on the recap. **Tone for all user-facing coaching text**: consistency over
    performance — life happens, nothing is owed, a shorter run still counts; name the real numbers,
    no guilt, no generic hype.
  - `ProgramCoordinator.swift`: the orchestration seam that ties the above to a `ModelContext` — seeding
    the program on first launch, picking "today's session", running the weekly adaptation check, and
    recording a finished run. Views should talk to `ProgramCoordinator`, not to `AdaptationEngine` or
    `ProgramScheduler` directly.
- **`Location/`** — run-tracking runtime, independent of SwiftUI:
  - `LocationTracker.swift`: `CLLocationManager` wrapper (`@MainActor`, `ObservableObject`). Filters GPS
    points by accuracy and implausible speed jumps before accepting them.
  - `RunSessionController.swift`: expands a session's intervals (respecting `repeatCount`) into a flat
    timeline and drives the per-second timer/interval advancement during an active run. Also runs a
    *free run* (no session: the runner switches run/walk manually). Both modes record
    `RecordedSegment`s (stored on `Run.segments`); `ActiveRunView` fills each segment's distance from
    `LocationTracker.distance(at:)` and `RunSummaryView` shows per-interval pace. Free runs are saved with
    `SessionKind.free` and no `plannedSessionID`, so they never complete a session or feed adaptation.
  - `SoundCueService.swift`: tone motif + `AVSpeechSynthesizer` cue on every interval switch, a 3-2-1 tick
    before it, a "N minutes left" chime at each whole minute of an interval, a halfway cue (snapped to a
    switch within 15 s, then merged into it), pause/resume and completion cues. Tones are synthesized at launch (`Tone` palette in A major:
    rising = more effort, falling = ease off) and played via `AVAudioEngine` on the app's `.playback`
    session, so they work on silent and locked. The session is active only while a cue sounds, then
    deactivated with `.notifyOthersOnDeactivation` so music/podcasts come back — keep that invariant.
- **`Views/`** — `RootView` (tab bar: Today / Free run / Plan / History), `FreeRunView` (starts an
  off-plan run/walk session), `HomeView` (today's session, week progress,
  adaptation feedback banner), `ActiveRunView` (full-screen, glanceable: big segment countdown colored by
  interval kind, session strip, next-up card, pause / hold-to-end — deliberately no map),
  `RunSummaryView` (post-run recap with the route polyline fitted on a map; also the History detail),
  `PlanView` (tap a week → `WeekDetailView`: full interval breakdown + start/restart the program at that week), `HistoryView`, and `Theme.swift` (shared colors, interval-kind colors, number formatting). All colors are light/dark adaptive tokens (`Theme.text`, `.accent`, `.onAccent`, `.card`, `.secondaryText`) — use them, never hard-coded `.white`/`.mint`. The `Appearance` setting (Dark default / Light / System, picker in `AboutView`) is applied as a window `overrideUserInterfaceStyle` from `PaceApp`; `ActiveRunView`’s run screen is always forced dark.
  Views own `@Query`/`@StateObject` wiring and call into `ProgramCoordinator`; they should not contain
  scheduling or adaptation logic themselves.

**Interval semantics**: consecutive `IntervalDefinition`s sharing the same `repeatCount > 1` form one
repeated block (`[run ×8, walk ×8]` = run/walk alternating 8 times). Always expand via
`[IntervalDefinition].timeline`, never by repeating each interval on its own.

**Week blocks**: a repeated week keeps its week number, so "the current week" is
`TrainingAnalyzer.currentBlock` (latest calendar week holding that week number), not a plain
`week ==` filter. Sessions left `planned` when a week is evaluated become `skipped`.

**Data flow for a run**: `HomeView` picks `todaysSession` via `ProgramCoordinator` → presents
`ActiveRunView(session:)` via `.fullScreenCover(item:)` → `RunSessionController` drives the interval timer while
`LocationTracker` records GPS → on finish, `ProgramCoordinator.recordRun` persists a `Run` and marks the
`PlannedSession` completed → `ActiveRunView` swaps to `RunSummaryView` → next `HomeView.onAppear`, `ProgramCoordinator.evaluateWeeksIfNeeded` runs
`TrainingAnalyzer` + `AdaptationEngine` once a week's last session date has passed, applies the result via
`AdaptationApplier`, and stores the explanation on `ActiveProgram.lastFeedback` for the Home banner.

**Known SwiftUI gotcha already hit once**: don't present a sheet with `.sheet(isPresented:)` driven by a
separate `@State` value for the content (e.g. a `Bool` plus an optional model). The content closure can
read the optional as `nil` even though it was just set, because the two `@State` writes aren't guaranteed
to commit as one transaction before the sheet closure evaluates. Use `.sheet(item:)` / `.fullScreenCover(item:)` bound
directly to the optional instead (see `HomeView`) — this is the pattern already in use, don't regress it.
