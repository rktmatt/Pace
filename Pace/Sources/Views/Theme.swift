import SwiftUI
import UIKit

/// Small set of shared visual tokens so Home, the run screen and the recap
/// agree on colors and number formatting. Every color resolves per color
/// scheme: dark is the signature look, light keeps the same contrast and
/// confidence with a deeper mint so the accent stays legible on white.
enum Theme {
    static let backgroundTop = Color(light: Color(red: 0.97, green: 0.98, blue: 0.98), dark: .black)
    static let background = LinearGradient(
        colors: [backgroundTop, Color(light: Color(red: 0.89, green: 0.94, blue: 0.94), dark: Color(red: 0.06, green: 0.11, blue: 0.13))],
        startPoint: .top,
        endPoint: .bottom
    )
    /// Primary foreground: white on dark, near-black ink on light.
    static let text = Color(light: Color(red: 0.04, green: 0.08, blue: 0.09), dark: .white)
    static let card = Color(light: .black.opacity(0.06), dark: .white.opacity(0.08))
    static let secondaryText = text.opacity(0.52)
    /// Brand mint. Deepened in light mode so text and strokes keep contrast on white.
    static let accent = Color(light: Color(red: 0.0, green: 0.56, blue: 0.48), dark: .mint)
    /// Foreground on an `accent` fill.
    static let onAccent = Color(light: .white, dark: .black)
}

/// The user's appearance choice (About sheet). Dark is the default look.
enum Appearance: String, CaseIterable, Identifiable {
    case dark, light, system

    static let storageKey = "appearance"

    var id: Self { self }

    var label: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "System"
        }
    }

    private var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: .unspecified
        }
    }

    /// Applied on the windows rather than via `preferredColorScheme`, which
    /// doesn't reliably return to the system setting once it has been forced.
    /// Sheets and full-screen covers inherit it.
    @MainActor
    func apply() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = interfaceStyle
            }
        }
    }
}

extension Color {
    /// A color that resolves differently in light and dark mode.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .light ? UIColor(light) : UIColor(dark)
        })
    }
}

extension IntervalKind {
    /// Segment color, readable at a glance mid-run: mint = run, amber = walk,
    /// blue = easy warm up / cool down.
    var color: Color {
        switch self {
        case .run: Theme.accent
        case .walk: Color(light: Color(red: 0.86, green: 0.5, blue: 0.0), dark: Color(red: 1.0, green: 0.72, blue: 0.28))
        case .warmup, .cooldown: Color(light: Color(red: 0.16, green: 0.42, blue: 0.86), dark: Color(red: 0.45, green: 0.68, blue: 1.0))
        }
    }

    var symbol: String {
        switch self {
        case .run: "figure.run"
        case .walk: "figure.walk"
        case .warmup: "flame"
        case .cooldown: "wind"
        }
    }
}

enum Format {
    /// 75 → "1:15", 3725 → "1:02:05".
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    /// Countdown rounds up so a segment reads "1:30" for its whole first second
    /// and never shows "0:00" while still running.
    static func countdown(_ interval: TimeInterval) -> String {
        clock(interval.rounded(.up))
    }

    static func kilometers(_ meters: Double) -> String {
        String(format: "%.2f", meters / 1000)
    }

    static func pace(seconds: TimeInterval, meters: Double) -> String {
        guard meters > 50 else { return "—" }
        let perKm = seconds / (meters / 1000)
        guard perKm.isFinite, perKm < 3600 else { return "—" }
        return clock(perKm)
    }

    /// One line for a whole week: its structure when every session is the same,
    /// otherwise how the longest run builds across the week ("Longest run 8:00 → 10:00").
    static func weekStructure(_ sessions: [[IntervalDefinition]]) -> String {
        let structures = sessions.map(structure)
        guard Set(structures).count > 1 else { return structures.first ?? "" }
        let longest = sessions.map(\.longestRunSeconds)
        guard let first = longest.first, let last = longest.last, first != last else { return structures.joined(separator: " / ") }
        return "Longest run \(clock(TimeInterval(first))) → \(clock(TimeInterval(last)))"
    }

    /// "8 × 1:00 run · 1:30 walk" — the main set, ignoring warm up / cool down.
    static func structure(_ intervals: [IntervalDefinition]) -> String {
        var described: [String] = []
        for block in intervals.repeatBlocks {
            let main = block.intervals.filter { $0.kind == .run || $0.kind == .walk }
            guard !main.isEmpty else { continue }
            let parts: [String] = main.map { interval in
                let duration = clock(TimeInterval(interval.durationSeconds))
                return "\(duration) \(interval.kind.voicePrompt.lowercased())"
            }
            let body = parts.joined(separator: " · ")
            described.append(block.repeatCount > 1 ? "\(block.repeatCount) × \(body)" : body)
        }
        return described.joined(separator: ", ")
    }
}

extension View {
    /// Fades scrolled content out under the status bar so it never collides
    /// with the clock.
    func statusBarScrim() -> some View {
        overlay(alignment: .top) {
            GeometryReader { proxy in
                LinearGradient(colors: [Theme.backgroundTop, Theme.backgroundTop, Theme.backgroundTop.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: proxy.safeAreaInsets.top + 28)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
        }
    }
}
