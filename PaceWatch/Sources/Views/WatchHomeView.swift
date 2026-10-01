import SwiftUI

/// What to start: the next planned session (as synced from the phone), or a free run.
struct WatchHomeView: View {
    @EnvironmentObject private var sync: WatchSyncStore
    @State private var request: RunRequest?
    @AppStorage(CombinedCues.voiceCuesKey) private var voiceCues = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let next = sync.upcoming.first {
                        NextSessionCard(session: next, totalWeeks: sync.schedule?.totalWeeks, palette: sync.palette) {
                            request = RunRequest(session: next)
                        }
                    } else {
                        Text(sync.schedule == nil
                             ? "Your plan isn't on this Watch yet. Open Pace on the iPhone paired with it."
                             : "No planned sessions left. A free run still counts.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        request = RunRequest(session: nil)
                    } label: {
                        Label("Free run", systemImage: "stopwatch")
                            .font(.system(.body, design: .rounded).weight(.bold))
                            .frame(maxWidth: .infinity)
                    }

                    if sync.upcoming.count > 1 {
                        Text("UP NEXT")
                            .font(WatchTheme.label)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                        ForEach(sync.upcoming.dropFirst()) { session in
                            UpcomingRow(session: session)
                        }
                    }

                    Toggle(isOn: $voiceCues) {
                        Label("Voice cues", systemImage: "speaker.wave.2.fill")
                            .font(.footnote.weight(.semibold))
                    }
                    .padding(.top, 6)

                    if sync.pendingRunCount > 0 {
                        Label(sync.pendingRunCount == 1 ? "1 run waiting for your iPhone" : "\(sync.pendingRunCount) runs waiting for your iPhone", systemImage: "iphone.radiowaves.left.and.right")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Clear of the rounded corners: text never runs into the curve.
                .padding(.horizontal, 10)
            }
            .navigationTitle("Pace")
        }
        .fullScreenCover(item: $request) { request in
            WatchRunView(session: request.session, palette: sync.palette)
        }
    }
}

/// One run to start; `session` is nil for a free run.
struct RunRequest: Identifiable {
    let id = UUID()
    let session: WatchSession?
}

private struct NextSessionCard: View {
    let session: WatchSession
    let totalWeeks: Int?
    let palette: String
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(weekLabel)
                .font(WatchTheme.label)
                .foregroundStyle(WatchTheme.accent(palette))
            Text(session.title.uppercased())
                .font(.system(size: 20, weight: .black, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text("\(session.plannedDurationSeconds / 60) min · \(Format.structure(session.intervals))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let note = session.adjustmentNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            Button(action: start) {
                Label("START", systemImage: "figure.run")
                    .font(.system(.body, design: .rounded).weight(.black))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(.black)
            .padding(.top, 6)
        }
    }

    private var weekLabel: String {
        let day = Calendar.current.isDateInToday(session.scheduledAt)
            ? "TODAY"
            : session.scheduledAt.formatted(.dateTime.weekday(.abbreviated)).uppercased()
        let week = totalWeeks.map { "WEEK \(session.week)/\($0)" } ?? "WEEK \(session.week)"
        return "\(week) · \(day)"
    }
}

private struct UpcomingRow: View {
    let session: WatchSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(session.scheduledAt.formatted(.dateTime.weekday(.wide)))
                    .font(.footnote.weight(.semibold))
                Text("Week \(session.week) · \(session.plannedDurationSeconds / 60) min")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
