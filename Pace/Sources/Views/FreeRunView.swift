import SwiftUI
import SwiftData

/// Start a self-paced run outside the program: the runner switches between run
/// and walk whenever they like. Saved to History with a per-segment recap, but
/// never counted toward the plan.
struct FreeRunView: View {
    @Query(sort: \Run.startedAt, order: .reverse) private var runs: [Run]

    /// No content depends on separate state here, so a plain Bool is safe for
    /// the cover (unlike the session-driven cover on Home).
    @State private var isRunning = false

    private var freeRuns: [Run] { runs.filter { $0.sessionKind == .free } }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("FREE RUN")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .tracking(2)

                    Text("RUN AND WALK\nAS YOU FEEL")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .lineSpacing(-4)

                    VStack(alignment: .leading, spacing: 16) {
                        Step(symbol: IntervalKind.walk.symbol, color: IntervalKind.walk.color, text: "Starts walking, timer counting up.")
                        Step(symbol: "arrow.left.arrow.right", color: IntervalKind.run.color, text: "Tap the big button to switch between run and walk, as often as you like.")
                        Step(symbol: "list.bullet.rectangle", color: Theme.text, text: "The recap shows the pace of every run and walk you did.")
                    }

                    SwipeToStartView(title: "SWIPE TO START") {
                        isRunning = true
                    }

                    Text("Free runs are saved to History. They don't change your plan.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)

                    if !freeRuns.isEmpty {
                        HStack(spacing: 0) {
                            Metric(value: "\(freeRuns.count)", label: "FREE RUNS")
                            Metric(value: Format.kilometers(freeRuns.reduce(0) { $0 + $1.distanceMeters }), label: "KM")
                            Metric(value: Format.clock(freeRuns.reduce(0) { $0 + $1.duration }), label: "TIME")
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(24)
            }
        }
        .statusBarScrim()
        .foregroundStyle(Theme.text)
        .fullScreenCover(isPresented: $isRunning) {
            ActiveRunView(session: nil)
        }
    }
}

private struct Step: View {
    let symbol: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .font(.headline.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 26)
            Text(text)
                .font(.body)
                .foregroundStyle(Theme.text.opacity(0.78))
        }
    }
}
