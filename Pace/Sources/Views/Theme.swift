import SwiftUI
import UIKit

/// Small set of shared visual tokens so Home, the run screen and the recap
/// agree on colors and number formatting. Every color resolves per color
/// scheme: dark is the signature look, light keeps the same contrast and
/// confidence with a deeper mint so the accent stays legible on white.
enum Theme {
    static let backgroundTop = Color.themed(
        mint: Color(light: Color(red: 0.97, green: 0.98, blue: 0.98), dark: .black),
        pink: Color(light: Color(red: 1.0, green: 0.96, blue: 0.98), dark: Color(red: 0.07, green: 0.0, blue: 0.04))
    )
    static let background = LinearGradient(
        colors: [backgroundTop, Color.themed(
            mint: Color(light: Color(red: 0.89, green: 0.94, blue: 0.94), dark: Color(red: 0.06, green: 0.11, blue: 0.13)),
            pink: Color(light: Color(red: 0.99, green: 0.86, blue: 0.92), dark: Color(red: 0.20, green: 0.03, blue: 0.13))
        )],
        startPoint: .top,
        endPoint: .bottom
    )
    /// Primary foreground: white on dark, near-black ink on light.
    static let text = Color.themed(
        mint: Color(light: Color(red: 0.04, green: 0.08, blue: 0.09), dark: .white),
        pink: Color(light: Color(red: 0.20, green: 0.02, blue: 0.12), dark: .white)
    )
    static let card = Color.themed(
        mint: Color(light: .black.opacity(0.06), dark: .white.opacity(0.08)),
        pink: Color(light: Color(red: 0.85, green: 0.10, blue: 0.45).opacity(0.08), dark: Color(red: 1.0, green: 0.55, blue: 0.80).opacity(0.10))
    )
    static let secondaryText = text.opacity(0.52)
    /// Brand accent. Deepened in light mode so text and strokes keep contrast on white.
    static let accent = Color.themed(
        mint: Color(light: Color(red: 0.0, green: 0.56, blue: 0.48), dark: .mint),
        pink: Color(light: Color(red: 0.84, green: 0.09, blue: 0.45), dark: Color(red: 1.0, green: 0.42, blue: 0.72))
    )
    /// Foreground on an `accent` fill.
    static let onAccent = Color(light: .white, dark: .black)
}

/// Color palette (About sheet). Mint is the signature look; pink is an
/// exploration — same contrast and boldness, different hue.
enum Palette: String, CaseIterable, Identifiable {
    case mint, pink

    static let storageKey = "palette"

    var id: Self { self }

    var label: String {
        switch self {
        case .mint: "Mint"
        case .pink: "Pink"
        }
    }

    /// Set as a window trait so every `Color.themed` re-resolves in place —
    /// no view identity reset, open sheets stay open.
    @MainActor
    func apply() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.traitOverrides[PaletteTrait.self] = self
            }
        }
    }

    /// Alternate icon in the asset catalog (`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`);
    /// nil is the primary mint icon.
    private var iconName: String? {
        switch self {
        case .mint: nil
        case .pink: "AppIconPink"
        }
    }

    /// Swaps the home screen icon to match. iOS shows its own confirmation
    /// alert on every change, so only call it when the name actually differs.
    @MainActor
    func applyIcon() {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.alternateIconName != iconName else { return }
        app.setAlternateIconName(iconName)
    }
}

struct PaletteTrait: UITraitDefinition {
    static let defaultValue = Palette.mint
    static let affectsColorAppearance = true
    static let identifier = "com.matthieuroussel.Pace.palette"
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

extension Color {
    /// A color that resolves per palette; each variant can itself be light/dark adaptive.
    static func themed(mint: Color, pink: Color) -> Color {
        Color(uiColor: UIColor { traits in
            let variant = traits[PaletteTrait.self] == .pink ? pink : mint
            return UIColor(variant).resolvedColor(with: traits)
        })
    }
}

extension IntervalKind {
    /// Segment color, readable at a glance mid-run: accent = run, amber = walk,
    /// blue (lavender in pink) = easy warm up / cool down.
    var color: Color {
        switch self {
        case .run: Theme.accent
        case .walk: Color(light: Color(red: 0.86, green: 0.5, blue: 0.0), dark: Color(red: 1.0, green: 0.72, blue: 0.28))
        case .warmup, .cooldown: Color.themed(
            mint: Color(light: Color(red: 0.16, green: 0.42, blue: 0.86), dark: Color(red: 0.45, green: 0.68, blue: 1.0)),
            pink: Color(light: Color(red: 0.45, green: 0.30, blue: 0.85), dark: Color(red: 0.72, green: 0.62, blue: 1.0))
        )
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
