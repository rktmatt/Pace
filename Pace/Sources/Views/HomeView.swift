import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ActiveProgram.startedAt) private var programs: [ActiveProgram]
    @Query(sort: \PlannedSession.scheduledAt) private var sessions: [PlannedSession]
    @Query(sort: \Run.startedAt) private var runs: [Run]
    @Query(sort: \AdaptationRecord.date, order: .reverse) private var records: [AdaptationRecord]

    @State private var sessionForRun: PlannedSession?
    @State private var showingAbout = false
    @ObservedObject private var quickActions = QuickActionRouter.shared

    private var coordinator: ProgramCoordinator { ProgramCoordinator(context: modelContext) }
    private var program: ActiveProgram? { programs.first }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    if let program {
                        weekLabel(program)
                        todayCard

                        if let feedback = program.lastFeedback {
                            feedbackCard(feedback)
                        }

                        startButton
                        weekMetrics(program)

                        if runs.isEmpty && program.currentWeek == 1 {
                            Text("Already running? Open Plan, tap the week that matches your level and start from there.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    } else {
                        ProgressView().tint(Theme.accent)
                    }
                }
                .padding(24)
            }
        }
        .statusBarScrim()
        .onAppear {
            refresh()
            startFromQuickAction()
        }
        .onChange(of: quickActions.pending) { _, _ in startFromQuickAction() }
        .fullScreenCover(item: $sessionForRun) { session in
            ActiveRunView(session: session)
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
    }

    private func refresh() {
        coordinator.ensureProgramSeeded()
        coordinator.migrateToCurrentProgramVersion()
        if let program = coordinator.activeProgram() {
            coordinator.evaluateWeeksIfNeeded(program: program)
        }
    }

    /// "Start week N" quick action: same as swiping to start the next session.
    private func startFromQuickAction() {
        guard quickActions.pending == .startSession else { return }
        quickActions.pending = nil
        if sessionForRun == nil { sessionForRun = todaysSession }
    }

    private var header: some View {
        HStack {
            Text("PACE")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .tracking(2)
            Spacer()
            Button {
                showingAbout = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityLabel("About Pace")
        }
    }

    private func weekLabel(_ program: ActiveProgram) -> some View {
        Text("WEEK \(program.currentWeek) / \(Couch5KProgram.definition.totalWeeks)")
            .font(.caption.weight(.bold))
            .foregroundStyle(Theme.accent)
            .tracking(1.4)
    }

    @ViewBuilder
    private var todayCard: some View {
        if let session = todaysSession {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(dayLabel(for: session.scheduledAt)) · \(session.kind.label.uppercased())")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                Text("\(session.plannedDurationSeconds / 60) MIN\n\(session.title.uppercased())")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .lineSpacing(-4)
                Text(Format.structure(session.intervals))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 2)
            }
        } else {
            Text("No session scheduled")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.text.opacity(0.6))
        }
    }

    private func feedbackCard(_ feedback: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(records.first?.kind.headline ?? "Your plan has adjusted", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.accent)
            Text(feedback)
                .font(.body)
                .foregroundStyle(Theme.text.opacity(0.78))
        }
        .padding(20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private var startButton: some View {
        SwipeToStartView(isEnabled: todaysSession != nil) {
            sessionForRun = todaysSession
        }
    }

    private func weekMetrics(_ program: ActiveProgram) -> some View {
        let weekSessions = coordinator.currentWeekSessions(program: program, allSessions: sessions)
        let completed = weekSessions.filter { $0.state == .completed }.count
        let weekRuns = runs.filter { run in
            guard let id = run.plannedSessionID else { return false }
            return weekSessions.contains { $0.id == id }
        }
        let minutes = Int(weekRuns.reduce(0.0) { $0 + $1.duration } / 60)
        let km = weekRuns.reduce(0.0) { $0 + $1.distanceMeters } / 1000

        return HStack(spacing: 0) {
            Metric(value: "\(completed) / \(weekSessions.count)", label: "SESSIONS")
            Metric(value: "\(minutes)", label: "MINUTES")
            Metric(value: String(format: "%.1f", km), label: "KM")
        }
        .padding(.top, 6)
    }

    private func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "TODAY" }
        if calendar.isDateInTomorrow(date) { return "TOMORROW" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased()
    }

    private var todaysSession: PlannedSession? {
        coordinator.todaysSession(allSessions: sessions)
    }
}

struct Metric: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.weight(.bold).monospacedDigit())
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(Theme.text.opacity(0.48)).tracking(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [ActiveProgram.self, PlannedSession.self, Run.self, RoutePoint.self, AdaptationRecord.self], inMemory: true)
}
