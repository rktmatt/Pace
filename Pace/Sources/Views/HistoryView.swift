import SwiftUI
import SwiftData

/// Every finished run, newest first; each opens its route recap.
struct HistoryView: View {
    @Query(sort: \Run.startedAt, order: .reverse) private var runs: [Run]
    @Query private var sessions: [PlannedSession]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("HISTORY")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .tracking(2)

                        if runs.isEmpty {
                            emptyState
                        } else {
                            totals
                            LazyVStack(spacing: 10) {
                                ForEach(runs) { run in
                                    NavigationLink(value: run) {
                                        RunRow(run: run, title: title(for: run))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(24)
                }
            }
            .statusBarScrim()
            .foregroundStyle(Theme.text)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Run.self) { run in
                RunSummaryView(run: run, title: title(for: run))
                    .toolbar(.visible, for: .navigationBar)
            }
        }
    }

    private func title(for run: Run) -> String {
        sessions.first { $0.id == run.plannedSessionID }?.title ?? run.sessionKind.label
    }

    private var totals: some View {
        HStack(spacing: 0) {
            Metric(value: "\(runs.count)", label: "RUNS")
            Metric(value: Format.kilometers(runs.reduce(0) { $0 + $1.distanceMeters }), label: "KM")
            Metric(value: Format.clock(runs.reduce(0) { $0 + $1.duration }), label: "TIME")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "map")
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.accent)
            Text("No runs yet")
                .font(.title2.weight(.black))
            Text("Finished sessions show up here, each with a map of your route.")
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.top, 40)
    }
}

private struct RunRow: View {
    let run: Run
    let title: String

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(run.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.headline.weight(.bold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Format.kilometers(run.distanceMeters)) km")
                    .font(.headline.weight(.black).monospacedDigit())
                Text(Format.clock(run.duration))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
    }
}
