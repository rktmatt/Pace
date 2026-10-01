import SwiftUI

/// The run on the wrist: the segment countdown in the interval's color, felt
/// through haptics at every switch. Swipe right for pause / end. Same engine as
/// the phone (`RunSessionController`, `LocationTracker`); the finished run is
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
        let cues = HapticCueService()
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
            HStack {
                if let kind = runController.currentKind {
                    Label(runController.isPaused ? "PAUSED" : kind.voicePrompt.uppercased(), systemImage: WatchTheme.symbol(for: kind))
                }
                Spacer()
                Text(Format.clock(runController.elapsed))
                    .foregroundStyle(.secondary)
            }
            .font(WatchTheme.label)
            .foregroundStyle(kindColor)

            Text(runController.isFreeRun ? Format.clock(runController.timeInSegment) : Format.countdown(runController.timeRemainingInInterval))
                .font(WatchTheme.numerals(56))
                .foregroundStyle(kindColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .opacity(runController.isPaused ? 0.5 : 1)

            if !runController.isFreeRun, !isLuminanceReduced {
                ProgressView(value: runController.intervalProgress)
                    .tint(kindColor)
            }

            if runController.isFreeRun {
                switchButton
            } else if let next = runController.nextInterval {
                Text("NEXT  \(next.kind.voicePrompt.uppercased()) \(Format.clock(TimeInterval(next.durationSeconds)))")
                    .font(WatchTheme.label)
                    .foregroundStyle(WatchTheme.color(for: next.kind, palette: palette))
                    .padding(.top, 2)
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
            }
        }
        .padding(.horizontal, 4)
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
