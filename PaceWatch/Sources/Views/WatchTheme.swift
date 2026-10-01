import SwiftUI

/// The Watch is always dark: same bold numerals and accent as the phone,
/// following the palette picked there.
enum WatchTheme {
    static func accent(_ palette: String) -> Color {
        palette == "pink" ? Color(red: 1.0, green: 0.42, blue: 0.72) : .mint
    }

    /// Run = accent, walk = amber, warm up / cool down = blue (lavender in pink).
    static func color(for kind: IntervalKind, palette: String) -> Color {
        switch kind {
        case .run: accent(palette)
        case .walk: Color(red: 1.0, green: 0.72, blue: 0.28)
        case .warmup, .cooldown: palette == "pink" ? Color(red: 0.72, green: 0.62, blue: 1.0) : Color(red: 0.45, green: 0.68, blue: 1.0)
        }
    }

    static func symbol(for kind: IntervalKind) -> String {
        switch kind {
        case .run: "figure.run"
        case .walk: "figure.walk"
        case .warmup: "flame"
        case .cooldown: "wind"
        }
    }

    static func numerals(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded).monospacedDigit()
    }

    static let label = Font.system(size: 12, weight: .bold, design: .rounded)
}
