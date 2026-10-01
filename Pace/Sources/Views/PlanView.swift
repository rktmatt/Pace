import SwiftUI
import SwiftData

/// The whole program at a glance: phases with their rationale, and each week's
/// sessions as actually scheduled (including any adaptations).
struct PlanView: View {
    @Query(sort: \ActiveProgram.startedAt) private var programs: [ActiveProgram]
    @Query(sort: \PlannedSession.scheduledAt) private var sessions: [PlannedSession]
    @Query(sort: \AdaptationRecord.date, order: .reverse) private var records: [AdaptationRecord]

    @State private var selectedWeek: WeekDefinition?

    private let definition = Couch5KProgram.definition
    private var program: ActiveProgram? { programs.first }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        ForEach(definition.phases) { phase in
                            phaseSection(phase)
                        }
                        if !records.isEmpty {
                            AdjustmentHistory(records: records)
                        }
                        references
                    }
                    .padding(24)
                }
                .onAppear {
                    if let week = program?.currentWeek, week > 1 {
                        proxy.scrollTo(week, anchor: .top)
                    }
                }
            }
        }
        .statusBarScrim()
        .foregroundStyle(Theme.text)
        .sheet(item: $selectedWeek) { week in
            WeekDetailView(
                week: week,
                phase: definition.phases.first { $0.weeks.contains(week) },
                sessions: TrainingAnalyzer.currentBlock(week: week.weekNumber, of: sessions),
                currentWeek: program?.currentWeek ?? 1
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PLAN")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .tracking(2)
            Text(definition.title.uppercased())
                .font(.system(size: 40, weight: .black, design: .rounded))
            Text(definition.summary)
                .font(.body)
                .foregroundStyle(Theme.text.opacity(0.78))
            Text("Tap a week to see its sessions, or to start the program from there.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)

            if let program {
                let current = min(program.currentWeek, definition.totalWeeks)
                VStack(alignment: .leading, spacing: 8) {
                    Text(program.currentWeek > definition.totalWeeks ? "PROGRAM COMPLETE" : "WEEK \(current) OF \(definition.totalWeeks)")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.accent)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.text.opacity(0.12))
                            Capsule().fill(Theme.accent)
                                .frame(width: geo.size.width * Double(program.currentWeek - 1) / Double(definition.totalWeeks))
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.top, 4)
            }
        }
    }

    private func phaseSection(_ phase: PhaseDefinition) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(phase.name.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.accent)
                Text(phase.rationale)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(phase.weeks) { week in
                Button {
                    selectedWeek = week
                } label: {
                    WeekCard(
                        week: week,
                        sessions: TrainingAnalyzer.currentBlock(week: week.weekNumber, of: sessions),
                        wasRepeated: Set(sessions.filter { $0.week == week.weekNumber }.map { Calendar.current.startOfISOWeek(for: $0.scheduledAt) }).count > 1,
                        currentWeek: program?.currentWeek ?? 1
                    )
                }
                .buttonStyle(.plain)
                .id(week.weekNumber)
            }
        }
    }

    private var references: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BASED ON")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Theme.secondaryText)
            ForEach(definition.references, id: \.self) { reference in
                Text(reference)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.top, 8)
    }
}

private struct WeekCard: View {
    let week: WeekDefinition
    let sessions: [PlannedSession]
    let wasRepeated: Bool
    let currentWeek: Int

    private var isCurrent: Bool { week.weekNumber == currentWeek }
    private var isPast: Bool { week.weekNumber < currentWeek }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("WEEK \(week.weekNumber)")
                    .font(.headline.weight(.black))
                if isCurrent { Tag(text: "NOW", color: Theme.accent) }
                if week.isDeload { Tag(text: "LIGHTER", color: Theme.text.opacity(0.6)) }
                if wasRepeated { Tag(text: "REPEATED", color: Theme.text.opacity(0.6)) }
                if sessions.contains(where: { $0.adjustmentNote != nil && $0.state == .planned }) {
                    Tag(text: "ADJUSTED", color: Theme.accent.opacity(0.8))
                }
                Spacer()
                if isPast && sessions.contains(where: { $0.state == .completed }) {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(Theme.accent)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.secondaryText)
            }

            Text(Format.weekStructure(sessions.isEmpty ? week.sessions.map(\.intervals) : sessions.sorted { $0.scheduledAt < $1.scheduledAt }.map(\.intervals)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text.opacity(0.78))

            if sessions.isEmpty {
                Text(isPast ? "Before your starting week" : "Not scheduled")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                VStack(spacing: 8) {
                    ForEach(sessions) { session in
                        SessionRow(session: session)
                    }
                }
            }
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 20).stroke(Theme.accent.opacity(0.7), lineWidth: 1.5)
            }
        }
        .opacity(isPast ? 0.7 : 1)
    }
}

private struct SessionRow: View {
    let session: PlannedSession

    var body: some View {
        HStack {
            stateIcon
                .frame(width: 20)
            Text(session.scheduledAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(session.state == .skipped ? Theme.secondaryText : Theme.text)
            Spacer()
            Text("\(session.plannedDurationSeconds / 60) min")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch session.state {
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
        case .skipped:
            Image(systemName: "minus.circle").foregroundStyle(Theme.secondaryText)
        case .planned:
            Image(systemName: "circle").foregroundStyle(Theme.text.opacity(0.35))
        }
    }
}

/// Every weekly check, restart and program update, newest first — including
/// the weeks where nothing changed, so it reads as a record of consistency.
private struct AdjustmentHistory: View {
    let records: [AdaptationRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("YOUR WEEKS")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.accent)
                Text("Each week's check-in: what you did and what changed.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    RecordRow(record: record, isLast: index == records.count - 1)
                }
            }
        }
        .padding(.top, 8)
    }
}

private struct RecordRow: View {
    let record: AdaptationRecord
    let isLast: Bool

    private var color: Color {
        switch record.kind {
        case .onPlan, .held: Theme.accent
        case .restarted, .programUpdated: Theme.text.opacity(0.6)
        default: IntervalKind.walk.color
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle().fill(color).frame(width: 10, height: 10).padding(.top, 5)
                if !isLast {
                    Rectangle().fill(Theme.text.opacity(0.12)).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("WEEK \(record.week)")
                        .font(.subheadline.weight(.black))
                    Tag(text: record.kind.label, color: color)
                    Spacer()
                    Text(record.date.formatted(.dateTime.day().month(.abbreviated)).uppercased())
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }
                if record.hasNumbers {
                    Text("\(record.completedSessions) of \(record.plannedSessions) sessions · \(record.actualMinutes) of \(record.plannedMinutes) min")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.text.opacity(0.78))
                }
                Text(record.message)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 20)
        }
    }
}

private struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.black))
            .tracking(1)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay(Capsule().stroke(color, lineWidth: 1))
    }
}
