import SwiftUI
import SwiftData

/// The mid-run screen. Built to be read in a glance at arm's length: one huge
/// countdown for the current segment, its color telling you run vs walk, and
/// what comes next underneath. The route map lives on the recap, not here.
///
/// With no session it runs as a free run: the timer counts up and a big switch
/// button flips between run and walk whenever the runner decides.
struct ActiveRunView: View {
    let session: PlannedSession?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var location = LocationTracker()
    @StateObject private var runController: RunSessionController
    @State private var startedAt = Date.now
    @State private var completedRun: Run?

    /// Runs shorter than this are treated as accidental starts and not saved.
    private static let minimumRecordedDuration: TimeInterval = 60

    init(session: PlannedSession?) {
        self.session = session
        _runController = StateObject(wrappedValue: session.map(RunSessionController.init(session:)) ?? RunSessionController(freeRunStartingWith: .walk))
    }

    private var title: String { session?.title ?? SessionKind.free.label }

    var body: some View {
        Group {
            if let completedRun {
                RunSummaryView(run: completedRun, title: title) { dismiss() }
                    .transition(.opacity)
            } else {
                runContent
            }
        }
        .onAppear {
            startedAt = .now
            location.requestAuthorization()
            location.startTracking()
            runController.start()
        }
        .onChange(of: runController.isFinished) { _, finished in
            if finished { finish() }
        }
        .onDisappear {
            runController.stop()
            location.stopTracking()
        }
    }

    private var accent: Color {
        runController.currentKind?.color ?? Theme.accent
    }

    private var runContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [accent.opacity(runController.isPaused ? 0.08 : 0.30), .clear], center: .top, startRadius: 0, endRadius: 560)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8), value: runController.currentKind)

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 8)
                Group {
                    if runController.isFreeRun {
                        FreeRunStrip(segments: runController.segments, current: runController.freeKind, currentDuration: runController.timeInSegment)
                    } else {
                        SessionStrip(intervals: runController.expandedIntervals, elapsed: runController.elapsed)
                    }
                }
                .frame(height: 8)
                .padding(.top, 14)

                Spacer(minLength: 24)
                currentSegment
                Spacer(minLength: 24)

                if runController.isFreeRun {
                    switchButton
                } else {
                    nextUp
                }
                stats
                    .padding(.top, 22)
                controls
                    .padding(.top, 28)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
        }
        .foregroundStyle(Theme.text)
        // Always dark mid-run, whatever the app appearance: colored numerals on
        // black read best at a glance. The recap follows the user's choice.
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            Spacer()
            Text(runController.isFreeRun
                 ? "SEGMENT \(runController.segments.count + 1)"
                 : "\(min(runController.currentIntervalIndex + 1, runController.expandedIntervals.count)) / \(runController.expandedIntervals.count)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var currentSegment: some View {
        VStack(spacing: 6) {
            if let kind = runController.currentKind {
                Label(runController.isPaused ? "PAUSED" : kind.voicePrompt.uppercased(),
                      systemImage: runController.isPaused ? "pause.fill" : kind.symbol)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(runController.isPaused ? Theme.text.opacity(0.6) : accent)
                    .contentTransition(.opacity)
            }

            Text(runController.isFreeRun ? Format.clock(runController.timeInSegment) : Format.countdown(runController.timeRemainingInInterval))
                .font(.system(size: 136, weight: .black, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .opacity(runController.isPaused ? 0.45 : 1)
                .contentTransition(.numericText(countsDown: !runController.isFreeRun))
                .animation(.snappy, value: Int(runController.isFreeRun ? runController.timeInSegment : runController.timeRemainingInInterval.rounded(.up)))

            if !runController.isFreeRun {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.text.opacity(0.12))
                        Capsule().fill(accent)
                            .frame(width: proxy.size.width * runController.intervalProgress)
                    }
                }
                .frame(height: 6)
                .padding(.horizontal, 40)
                .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var nextUp: some View {
        HStack(spacing: 14) {
            if let next = runController.nextInterval {
                Image(systemName: next.kind.symbol)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(next.kind.color)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.secondaryText)
                    Text(next.kind.voicePrompt.uppercased())
                        .font(.title3.weight(.black))
                        .foregroundStyle(next.kind.color)
                }
                Spacer()
                Text(Format.clock(TimeInterval(next.durationSeconds)))
                    .font(.title2.weight(.bold).monospacedDigit())
            } else {
                Image(systemName: "flag.checkered")
                    .font(.title2.weight(.bold))
                    .frame(width: 34)
                Text("LAST SEGMENT")
                    .font(.title3.weight(.black))
                Spacer()
            }
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
    }

    /// Free run: one big target to flip effort without looking closely —
    /// colored and labelled with what it switches *to*.
    private var switchButton: some View {
        let target: IntervalKind = runController.freeKind == .run ? .walk : .run
        return Button {
            runController.switchFreeKind()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: target.symbol)
                    .font(.title.weight(.black))
                    .frame(width: 34)
                Text("SWITCH TO \(target.voicePrompt.uppercased())")
                    .font(.title3.weight(.black))
                    .tracking(1)
                Spacer()
                Image(systemName: "arrow.left.arrow.right")
                    .font(.title3.weight(.bold))
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 22)
            .frame(height: 84)
            .background(target.color, in: RoundedRectangle(cornerRadius: 22))
            .opacity(runController.isPaused ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(runController.isPaused)
        .sensoryFeedback(.impact(weight: .heavy), trigger: runController.freeKind)
        .accessibilityLabel("Switch to \(target.voicePrompt)")
    }

    private var stats: some View {
        HStack(spacing: 0) {
            Metric(value: Format.kilometers(location.distanceMeters), label: "KM")
            Metric(value: Format.pace(seconds: runController.elapsed, meters: location.distanceMeters), label: "PACE /KM")
            Metric(value: Format.clock(runController.elapsed), label: "TOTAL")
        }
    }

    @ViewBuilder
    private var controls: some View {
        if runController.isPaused {
            HStack(spacing: 40) {
                HoldToEndButton(label: runController.elapsed < Self.minimumRecordedDuration ? "HOLD TO DISCARD" : "HOLD TO END") {
                    finish()
                }
                RoundControl(symbol: "play.fill", label: "RESUME", fill: Theme.accent) {
                    togglePause()
                }
            }
        } else {
            RoundControl(symbol: "pause.fill", label: "PAUSE", fill: .white) {
                togglePause()
            }
        }
    }

    private func togglePause() {
        runController.togglePause()
        location.setPaused(runController.isPaused)
    }

    private func finish() {
        guard completedRun == nil else { return }
        runController.stop()
        location.stopTracking()

        guard runController.elapsed >= Self.minimumRecordedDuration else {
            dismiss()
            return
        }
        let segments = runController.recordedSegments.map { segment in
            var measured = segment
            measured.distanceMeters = max(0, location.distance(at: segment.endedAt) - location.distance(at: segment.startedAt))
            return measured
        }
        let run = ProgramCoordinator(context: modelContext).recordRun(
            startedAt: startedAt,
            endedAt: .now,
            activeDuration: runController.elapsed,
            distanceMeters: location.distanceMeters,
            routePoints: location.recordedPoints,
            segments: segments,
            for: session
        )
        withAnimation(.easeInOut(duration: 0.35)) {
            completedRun = run
        }
    }
}

/// The whole session as one strip: each segment's width is its duration, its
/// color its kind, filled as it's completed.
private struct SessionStrip: View {
    let intervals: [IntervalDefinition]
    let elapsed: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            let total = Double(intervals.reduce(0) { $0 + $1.durationSeconds })
            let spacing: CGFloat = 2
            let usable = proxy.size.width - spacing * CGFloat(max(intervals.count - 1, 0))
            HStack(spacing: spacing) {
                ForEach(Array(intervals.enumerated()), id: \.offset) { index, interval in
                    let start = intervals[..<index].reduce(0) { $0 + Double($1.durationSeconds) }
                    let fraction = min(max((elapsed - start) / Double(interval.durationSeconds), 0), 1)
                    let width = total > 0 ? usable * Double(interval.durationSeconds) / total : 0
                    ZStack(alignment: .leading) {
                        Rectangle().fill(interval.kind.color.opacity(0.22))
                        Rectangle().fill(interval.kind.color)
                            .frame(width: width * fraction)
                    }
                    .frame(width: width)
                }
            }
            .clipShape(Capsule())
        }
    }
}

/// Free run: the segments recorded so far plus the current one, each as wide
/// as its share of the run, so the run's shape builds up as it happens.
private struct FreeRunStrip: View {
    let segments: [RecordedSegment]
    let current: IntervalKind
    let currentDuration: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            let parts = segments.map { ($0.kind, $0.activeDuration) } + [(current, max(currentDuration, 1))]
            let total = parts.reduce(0) { $0 + $1.1 }
            let spacing: CGFloat = 2
            let usable = proxy.size.width - spacing * CGFloat(parts.count - 1)
            HStack(spacing: spacing) {
                ForEach(parts.indices, id: \.self) { index in
                    Rectangle()
                        .fill(parts[index].0.color)
                        .frame(width: max(usable * parts[index].1 / total, 2))
                }
            }
            .clipShape(Capsule())
        }
    }
}

private struct RoundControl: View {
    let symbol: String
    let label: String
    let fill: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 88, height: 88)
                    .background(fill, in: Circle())
                Text(label)
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: symbol)
    }
}

/// Ending a run can't be undone, so it takes a deliberate one-second hold
/// rather than a tap that a sweaty thumb could hit by accident.
private struct HoldToEndButton: View {
    let label: String
    let action: () -> Void

    @State private var progress: CGFloat = 0
    @State private var completed = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.text.opacity(0.12))
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(3)
                Image(systemName: "stop.fill")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.orange)
            }
            .frame(width: 88, height: 88)
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: 1.0) {
                completed = true
                action()
            } onPressingChanged: { pressing in
                withAnimation(pressing ? .linear(duration: 1.0) : .easeOut(duration: 0.2)) {
                    progress = pressing ? 1 : 0
                }
            }
            .sensoryFeedback(.success, trigger: completed)

            Text(label)
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("End run")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}
