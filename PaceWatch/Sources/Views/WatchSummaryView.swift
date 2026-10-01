import SwiftUI

/// Short recap on the wrist; the full one (route, splits, notes) is on the phone.
struct WatchSummaryView: View {
    let run: WatchRun
    let title: String
    let palette: String
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Label("DONE", systemImage: "checkmark.circle.fill")
                    .font(WatchTheme.label)
                    .foregroundStyle(WatchTheme.accent(palette))
                Text(title.uppercased())
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .lineLimit(2)

                stat(Format.clock(run.activeDuration), unit: nil, label: "TIME")
                stat(Format.kilometers(run.distanceMeters), unit: "KM", label: "DISTANCE")
                stat(Format.pace(seconds: run.activeDuration, meters: run.distanceMeters), unit: "/KM", label: "AVG PACE")
                if let average = run.averageHeartRate {
                    stat("\(Int(average.rounded()))", unit: "BPM", label: "AVG HEART RATE")
                }

                Text("Your iPhone will add it to your plan.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Done", action: done)
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(.black)
                    .padding(.top, 4)
            }
        }
    }

    private func stat(_ value: String, unit: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(WatchTheme.numerals(28))
                if let unit {
                    Text(unit).font(WatchTheme.label).foregroundStyle(.secondary)
                }
            }
            Text(label).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
        }
    }
}
