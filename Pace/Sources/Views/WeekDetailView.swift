import SwiftUI
import SwiftData

/// One program week in full: every session's interval breakdown, plus the
/// option to (re)start the program here — for runners arriving from another
/// plan or coming back after time off.
struct WeekDetailView: View {
    let week: WeekDefinition
    let phase: PhaseDefinition?
    /// The week as actually scheduled (may be adapted); empty if never scheduled.
    let sessions: [PlannedSession]
    let currentWeek: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingStart = false

    private let definition = Couch5KProgram.definition
    private var coordinator: ProgramCoordinator { ProgramCoordinator(context: modelContext) }
    private var isCurrent: Bool { week.weekNumber == currentWeek }

    /// Sessions sharing the exact same intervals are shown once, with their days.
    private var groups: [SessionGroup] {
        let items: [SessionGroup.Day] = sessions.isEmpty
            ? week.sessions.map { .init(label: Self.weekdayName($0.suggestedWeekday), state: nil, intervals: $0.intervals, kind: $0.kind) }
            : sessions.sorted { $0.scheduledAt < $1.scheduledAt }.map {
                .init(label: $0.scheduledAt.formatted(.dateTime.weekday(.abbreviated).day()).uppercased(), state: $0.state, intervals: $0.intervals, kind: $0.kind)
            }
        var groups: [SessionGroup] = []
        for item in items {
            if let index = groups.firstIndex(where: { $0.signature == item.signature }) {
                groups[index].days.append(item)
            } else {
                groups.append(SessionGroup(days: [item]))
            }
        }
        return groups
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    guidance
                    ForEach(adjustmentNotes, id: \.self) { note in
                        AdjustmentCard(note: note)
                    }
                    ForEach(groups) { group in
                        SessionGroupCard(group: group)
                    }
                    startButton
                }
                .padding(24)
                .padding(.top, 8)
            }
        }
        .foregroundStyle(Theme.text)
        .presentationDragIndicator(.visible)
        .alert(startTitle, isPresented: $confirmingStart) {
            Button(isCurrent ? "Restart" : "Start week \(week.weekNumber)") {
                coordinator.restartProgram(atWeek: week.weekNumber)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(startScheduleLabel) Upcoming sessions are replaced; completed runs stay in your history.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let phase {
                Text(phase.name.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.accent)
            }
            Text("WEEK \(week.weekNumber)")
                .font(.system(size: 48, weight: .black, design: .rounded))
            Text(Format.weekStructure(sessionIntervals))
                .font(.headline)
                .foregroundStyle(Theme.text.opacity(0.78))
            HStack(spacing: 16) {
                Label("\(week.sessions.count) sessions", systemImage: "calendar")
                Label(durationLabel, systemImage: "clock")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
        }
    }

    /// Distinct reasons the weekly check changed this week's upcoming sessions.
    private var adjustmentNotes: [String] {
        var seen: [String] = []
        for note in sessions.filter({ $0.state == .planned }).compactMap(\.adjustmentNote) where !seen.contains(note) {
            seen.append(note)
        }
        return seen
    }

    private var sessionIntervals: [[IntervalDefinition]] {
        sessions.isEmpty ? week.sessions.map(\.intervals) : sessions.sorted { $0.scheduledAt < $1.scheduledAt }.map(\.intervals)
    }

    /// "31 min each", or "32–37 min" when the sessions differ.
    private var durationLabel: String {
        let minutes = sessionIntervals.map { $0.reduce(0) { $0 + $1.durationSeconds * $1.repeatCount } / 60 }
        guard let low = minutes.min(), let high = minutes.max() else { return "" }
        return low == high ? "\(low) min each" : "\(low)–\(high) min"
    }

    /// When this week is the right starting point — grounded in the previous
    /// week's prescription, the same rule the program itself progresses by.
    private var guidance: some View {
        let text: String
        if week.weekNumber == 1 {
            text = "Start here if you're new to running or returning after a long break."
        } else {
            let previous = definition.weeks[week.weekNumber - 2]
            let hardest = previous.sessions.last?.intervals ?? []
            text = "Right for you if you can comfortably run week \(previous.weekNumber)'s hardest session: \(Format.structure(hardest))."
        }
        return Label {
            Text(text).foregroundStyle(Theme.text.opacity(0.78))
        } icon: {
            Image(systemName: "figure.run").foregroundStyle(Theme.accent)
        }
        .font(.subheadline)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var startButton: some View {
        Button {
            confirmingStart = true
        } label: {
            Text(isCurrent ? "RESTART THIS WEEK" : "START FROM WEEK \(week.weekNumber)")
                .font(.headline.weight(.black))
                .tracking(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .foregroundStyle(isCurrent ? Theme.text : Theme.onAccent)
                .background(isCurrent ? AnyShapeStyle(Theme.card) : AnyShapeStyle(Theme.accent), in: Capsule())
        }
        .padding(.top, 4)
    }

    private var startTitle: String {
        isCurrent ? "Restart week \(week.weekNumber)?" : "Start from week \(week.weekNumber)?"
    }

    /// "First session today, then Fri 2 and Sat 3." — the actual days, since a
    /// mid-week start packs the sessions into the days left.
    private var startScheduleLabel: String {
        let dates = coordinator.restartSchedule(atWeek: week.weekNumber)
            .filter { $0.week == week.weekNumber }
            .map(\.scheduledAt)
            .sorted()
        guard let first = dates.first else { return "" }
        func label(_ date: Date) -> String {
            Calendar.current.isDateInToday(date) ? "today" : date.formatted(.dateTime.weekday(.abbreviated).day())
        }
        let rest = dates.dropFirst().map(label)
        let then = rest.isEmpty ? "" : ", then " + ListFormatter.localizedString(byJoining: rest)
        return "First session \(label(first))\(then)."
    }

    private static func weekdayName(_ isoWeekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols // Sunday first
        return symbols[isoWeekday % 7].uppercased()
    }
}

private struct SessionGroup: Identifiable {
    struct Day {
        let label: String
        let state: CompletionState?
        let intervals: [IntervalDefinition]
        let kind: SessionKind

        var signature: [String] {
            intervals.map { "\($0.kind.rawValue)-\($0.durationSeconds)x\($0.repeatCount)" }
        }
    }

    var days: [Day]
    var id: String { days.map(\.label).joined() }
    var signature: [String] { days[0].signature }
    var intervals: [IntervalDefinition] { days[0].intervals }
}

private struct SessionGroupCard: View {
    let group: SessionGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.days[0].kind.label.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text(Format.clock(TimeInterval(group.intervals.reduce(0) { $0 + $1.durationSeconds * $1.repeatCount })))
                    .font(.title3.weight(.black).monospacedDigit())
            }

            HStack(spacing: 6) {
                ForEach(group.days.indices, id: \.self) { index in
                    DayChip(day: group.days[index])
                }
            }

            TimelineBar(intervals: group.intervals.timeline)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(group.intervals.repeatBlocks.indices, id: \.self) { index in
                    let block = group.intervals.repeatBlocks[index]
                    if block.repeatCount > 1 {
                        HStack(alignment: .center, spacing: 12) {
                            Text("\(block.repeatCount)×")
                                .font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
                                .foregroundStyle(Theme.accent)
                                .frame(minWidth: 44, alignment: .leading)
                            VStack(spacing: 8) {
                                ForEach(block.intervals) { IntervalRow(interval: $0) }
                            }
                            .padding(.leading, 12)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Theme.text.opacity(0.2)).frame(width: 2)
                            }
                        }
                    } else {
                        ForEach(block.intervals) { IntervalRow(interval: $0) }
                    }
                }
            }
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct DayChip: View {
    let day: SessionGroup.Day

    var body: some View {
        HStack(spacing: 4) {
            switch day.state {
            case .completed: Image(systemName: "checkmark").foregroundStyle(Theme.accent)
            case .skipped: Image(systemName: "minus").foregroundStyle(Theme.secondaryText)
            case .planned, nil: EmptyView()
            }
            Text(day.label)
        }
        .font(.caption2.weight(.black).monospacedDigit())
        .tracking(0.6)
        .foregroundStyle(day.state == .skipped ? Theme.secondaryText : Theme.text)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Theme.text.opacity(0.08), in: Capsule())
    }
}

private struct IntervalRow: View {
    let interval: IntervalDefinition

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: interval.kind.symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(interval.kind.color)
                .frame(width: 22)
            Text(interval.kind.voicePrompt)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(Format.clock(TimeInterval(interval.durationSeconds)))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.text.opacity(0.78))
        }
    }
}

/// The session's shape at a glance: one segment per interval, width
/// proportional to duration, colored like the run screen.
private struct TimelineBar: View {
    let intervals: [IntervalDefinition]

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 2
            let total = CGFloat(max(intervals.reduce(0) { $0 + $1.durationSeconds }, 1))
            let available = geo.size.width - spacing * CGFloat(max(intervals.count - 1, 0))
            HStack(spacing: spacing) {
                ForEach(intervals.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(intervals[index].kind.color)
                        .frame(width: max(available * CGFloat(intervals[index].durationSeconds) / total, 1))
                }
            }
        }
        .frame(height: 10)
    }
}
