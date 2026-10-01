import SwiftUI

/// The run on the wrist: the segment countdown in the interval's color, felt
/// through haptics at every switch. Swipe right for pause / end. Same engine as
/// the phone (`RunSessionController`, `LocationTracker`, `SoundCueService`
/// alongside haptics); the finished run is
/// sent to the phone, which records it and adapts the plan.
struct WatchRunView: View {
    let session: WatchSession?
    let palette: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @StateObject private var runController: RunSessionController
    @StateObject private var location = LocationTracker()
    @StateObject private var workout = WorkoutManager()
    @State private var startedAt = Date.now
    @State private var page = 1
    @State private var completedRun: WatchRun?

    private static let minimumRecordedDuration: TimeInterval = 60

    init(session: WatchSession?, palette: String) {
        self.session = session
        self.palette = palette
        let cues = CombinedCues.forWatch()
        _runController = StateObject(wrappedValue: session.map { RunSessionController(intervals: $0.intervals, cues: cues) } ?? RunSessionController(freeRunStartingWith: .walk, cues: cues))
    }

    var body: some View {
        Group {
            if let completedRun {
                WatchSummaryView(run: completedRun, title: session?.title ?? "Free run", palette: palette) {
                    dismiss()
                }
            } else {
                TabView(selection: $page) {
                    controls.tag(0)
                    metrics.tag(1)
                }
                .tabViewStyle(.page)
            }
        }
        // The cover is translucent on watchOS 26: without this, Home's buttons
        // show through as a blur under the run.
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            startedAt = .now
            location.requestAuthorization()
            location.startTracking()
            runController.start()
            Task { await workout.start() }
        }
        .onChange(of: runController.isFinished) { _, finished in
            if finished { finish() }
        }
        .onDisappear {
            runController.stop()
            location.stopTracking()
            workout.end()
        }
    }

    // MARK: - Pages

    private var kindColor: Color {
        runController.currentKind.map { WatchTheme.color(for: $0, palette: palette) } ?? WatchTheme.accent(palette)
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if runController.isFreeRun {
                    WatchFreeRunStrip(segments: runController.segments, current: runController.freeKind, currentDuration: runController.timeInSegment, palette: palette)
                } else {
                    WatchSessionStrip(intervals: runController.expandedIntervals, elapsed: runController.elapsed, palette: palette)
                }
            }
            .frame(height: 5)
            .padding(.bottom, 4)

            HStack {
                if let kind = runController.currentKind {
                    Label(runController.isPaused ? "PAUSED" : kind.voicePrompt.uppercased(),
                          systemImage: runController.isPaused ? "pause.fill" : WatchTheme.symbol(for: kind))
                        .foregroundStyle(runController.isPaused ? .secondary : kindColor)
                        .contentTransition(.opacity)
                }
                Spacer()
                Text(Format.clock(runController.elapsed))
                    .foregroundStyle(.secondary)
            }
            .font(WatchTheme.label)
            .animation(.easeInOut(duration: 0.3), value: runController.currentKind)

            Text(runController.isFreeRun ? Format.clock(runController.timeInSegment) : Format.countdown(runController.timeRemainingInInterval))
                .font(WatchTheme.numerals(58))
                .foregroundStyle(kindColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .opacity(runController.isPaused ? 0.45 : 1)
                // Rolling digits, like the phone; skipped in always-on,
                // where the display only refreshes once a second anyway.
                .contentTransition(isLuminanceReduced ? .identity : .numericText(countsDown: !runController.isFreeRun))
                .animation(isLuminanceReduced ? nil : .snappy, value: displayedSecond)

            if !runController.isFreeRun {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule().fill(kindColor)
                            .frame(width: proxy.size.width * runController.intervalProgress)
                    }
                }
                .frame(height: 4)
                .animation(.linear(duration: 0.25), value: runController.intervalProgress)
            }

            if runController.isFreeRun {
                switchButton
            } else if let next = runController.nextInterval {
                Label("NEXT  \(next.kind.voicePrompt.uppercased()) \(Format.clock(TimeInterval(next.durationSeconds)))", systemImage: WatchTheme.symbol(for: next.kind))
                    .font(WatchTheme.label)
                    .foregroundStyle(WatchTheme.color(for: next.kind, palette: palette))
                    .padding(.top, 4)
            } else {
                Label("LAST SEGMENT", systemImage: "flag.checkered")
                    .font(WatchTheme.label)
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline) {
                Text(Format.kilometers(location.distanceMeters))
                    .font(WatchTheme.numerals(20))
                Text("KM").font(WatchTheme.label).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "heart.fill").font(.footnote).foregroundStyle(.red)
                Text(workout.heartRate.map { "\(Int($0.rounded()))" } ?? "--")
                    .font(WatchTheme.numerals(20))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: workout.heartRate)
            }
        }
        .padding(.horizontal, 8)
        .containerBackground(for: .tabView) { glow }
    }

    /// Same glow as the phone's run screen: the interval's color washing in
    /// from the top, dimmed when paused or in always-on. Set as the page's
    /// container background, which replaces the system's tint-colored one.
    private var glow: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [kindColor.opacity(runController.isPaused || isLuminanceReduced ? 0.08 : 0.40), .clear], center: .top, startRadius: 0, endRadius: 200)
        }
        .animation(.easeInOut(duration: 0.8), value: runController.currentKind)
    }

    /// The whole second shown on the big numerals, so the digit roll fires
    /// once per change rather than on every 0.25 s tick.
    private var displayedSecond: Int {
        Int(runController.isFreeRun ? runController.timeInSegment : runController.timeRemainingInInterval.rounded(.up))
    }

    /// Free run: one big target to switch effort, easy to hit mid-stride.
    private var switchButton: some View {
        let next: IntervalKind = runController.freeKind == .run ? .walk : .run
        return Button {
            runController.switchFreeKind()
        } label: {
            Label(next == .run ? "RUN" : "WALK", systemImage: WatchTheme.symbol(for: next))
                .font(.system(.body, design: .rounded).weight(.black))
                .frame(maxWidth: .infinity)
        }
        .tint(WatchTheme.color(for: next, palette: palette))
        .buttonStyle(.borderedProminent)
        .foregroundStyle(.black)
        .disabled(runController.isPaused)
        .padding(.top, 4)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Button {
                runController.togglePause()
                location.setPaused(runController.isPaused)
                workout.setPaused(runController.isPaused)
                page = 1
            } label: {
                Label(runController.isPaused ? "Resume" : "Pause", systemImage: runController.isPaused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .tint(.yellow)

            Button(role: .destructive) {
                finish()
            } label: {
                Label(runController.elapsed < Self.minimumRecordedDuration ? "Discard" : "End", systemImage: "xmark")
                    .frame(maxWidth: .infinity)
            }
            .tint(.red)
        }
        .font(.system(.body, design: .rounded).weight(.bold))
        .buttonStyle(.bordered)
        .containerBackground(for: .tabView) { glow }
    }

    // MARK: - Finish

    private func finish() {
        guard completedRun == nil else { return }
        runController.stop()
        location.stopTracking()
        workout.end()

        guard runController.elapsed >= Self.minimumRecordedDuration else {
            dismiss()
            return
        }
        let segments = runController.recordedSegments.map { segment in
            var measured = segment
            measured.distanceMeters = max(0, location.distance(at: segment.endedAt) - location.distance(at: segment.startedAt))
            return measured
        }
        let run = WatchRun(
            id: UUID(),
            plannedSessionID: session?.id,
            startedAt: startedAt,
            endedAt: .now,
            activeDuration: runController.elapsed,
            distanceMeters: location.distanceMeters,
            segments: segments,
            route: location.recordedPoints,
            averageHeartRate: workout.averageHeartRate,
            maxHeartRate: workout.maxHeartRate
        )
        WatchSyncStore.shared.send(run)
        withAnimation(.easeInOut(duration: 0.3)) {
            completedRun = run
        }
    }
}

/// The whole session as one strip: each segment's width is its duration, its
/// color its kind, filled as it's completed — as on the phone.
private struct WatchSessionStrip: View {
    let intervals: [IntervalDefinition]
    let elapsed: TimeInterval
    let palette: String

    var body: some View {
        GeometryReader { proxy in
            let total = Double(intervals.reduce(0) { $0 + $1.durationSeconds })
            let spacing: CGFloat = 1.5
            let usable = proxy.size.width - spacing * CGFloat(max(intervals.count - 1, 0))
            HStack(spacing: spacing) {
                ForEach(Array(intervals.enumerated()), id: \.offset) { index, interval in
                    let start = intervals[..<index].reduce(0) { $0 + Double($1.durationSeconds) }
                    let fraction = min(max((elapsed - start) / Double(interval.durationSeconds), 0), 1)
                    let width = total > 0 ? usable * Double(interval.durationSeconds) / total : 0
                    let color = WatchTheme.color(for: interval.kind, palette: palette)
                    ZStack(alignment: .leading) {
                        Rectangle().fill(color.opacity(0.25))
                        Rectangle().fill(color).frame(width: width * fraction)
                    }
                    .frame(width: width)
                }
            }
            .clipShape(Capsule())
        }
    }
}

/// Free run: the segments so far plus the current one, each as wide as its duration.
private struct WatchFreeRunStrip: View {
    let segments: [RecordedSegment]
    let current: IntervalKind
    let currentDuration: TimeInterval
    let palette: String

    var body: some View {
        GeometryReader { proxy in
            let parts = segments.map { ($0.kind, $0.activeDuration) } + [(current, max(currentDuration, 1))]
            let total = parts.reduce(0) { $0 + $1.1 }
            let spacing: CGFloat = 1.5
            let usable = proxy.size.width - spacing * CGFloat(parts.count - 1)
            HStack(spacing: spacing) {
                ForEach(parts.indices, id: \.self) { index in
                    Rectangle()
                        .fill(WatchTheme.color(for: parts[index].0, palette: palette))
                        .frame(width: max(usable * parts[index].1 / total, 2))
                }
            }
            .clipShape(Capsule())
        }
    }
}
