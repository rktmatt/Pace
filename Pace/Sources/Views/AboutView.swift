import SwiftUI
import AVFoundation

/// About sheet: what the app stands for, where the source lives, and an
/// optional tip jar. Links open in the browser — nothing is tracked.
struct AboutView: View {
    /// A link whose URL is nil renders as "Coming soon" instead of a dead button.
    enum Links {
        static let sourceCode = URL(string: "https://github.com/rktmatt/Pace")
        static let tip = URL(string: "https://ko-fi.com/rktmatt")
    }

    @Environment(\.dismiss) private var dismiss
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .dark
    @AppStorage(Palette.storageKey) private var palette: Palette = .mint
    /// Empty = automatic (best installed voice).
    @AppStorage(SoundCueService.voiceStorageKey) private var voiceID = ""
    @State private var voices = SoundCueService.availableVoices()
    /// Created on first preview, so opening About doesn't touch the audio session.
    @State private var previewCues: SoundCueService?

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    principles
                    appearancePicker
                    voicePicker
                    VStack(spacing: 12) {
                        linkRow(
                            title: "Source code",
                            subtitle: "Open source on GitHub",
                            systemImage: "chevron.left.forwardslash.chevron.right",
                            url: Links.sourceCode
                        )
                        linkRow(
                            title: "Buy me a coffee",
                            subtitle: "Pace is free. Tips keep it that way.",
                            systemImage: "mug.fill",
                            url: Links.tip
                        )
                    }
                    Text("VERSION \(version)")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .padding(24)
            }
        }
        .foregroundStyle(Theme.text)
        // Voices downloaded in Settings show up without reopening the sheet.
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
            voices = SoundCueService.availableVoices()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 14) {
                Text("ABOUT")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .tracking(2)
                Text("PACE")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                Text("Evidence-based training that adapts to your real life.")
                    .font(.body)
                    .foregroundStyle(Theme.text.opacity(0.78))
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .frame(width: 36, height: 36)
                    .background(Theme.card, in: Circle())
            }
            .accessibilityLabel("Close")
        }
    }

    private var principles: some View {
        VStack(alignment: .leading, spacing: 14) {
            principle("lock.fill", "Private by default", "No account, no tracking, no ads. Your runs stay on this device.")
            principle("checklist", "Structured programs", "Plans are hand-built from training research, never generated.")
            principle("arrow.triangle.2.circlepath", "Adapts to you", "Missed a week? The plan adjusts conservatively and tells you why.")
        }
        .padding(20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private var appearancePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Appearance", systemImage: "circle.lefthalf.filled")
                .font(.headline.weight(.bold))
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            Picker("Color", selection: $palette) {
                ForEach(Palette.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            Text("The run screen stays dark either way, for glanceability.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private var voicePicker: some View {
        let hasNaturalVoice = voices.contains { $0.quality != .default }
        return VStack(alignment: .leading, spacing: 12) {
            Label("Voice", systemImage: "waveform")
                .font(.headline.weight(.bold))
            VStack(spacing: 0) {
                voiceRow(
                    title: "Automatic",
                    detail: voices.first.map { "Best installed · \($0.name)" } ?? "System voice",
                    isSelected: voiceID.isEmpty || !voices.contains { $0.identifier == voiceID }
                ) {
                    voiceID = ""
                    preview(voices.first)
                }
                ForEach(voices, id: \.identifier) { voice in
                    Divider().overlay(Theme.secondaryText.opacity(0.2))
                    voiceRow(title: voice.name, detail: Self.voiceDetail(voice), isSelected: voice.identifier == voiceID) {
                        voiceID = voice.identifier
                        preview(voice)
                    }
                }
            }
            Text(hasNaturalVoice
                 ? "Tap a voice to hear it. More voices: Settings → Accessibility → Read & Speak → Voices."
                 : "Only basic voices are installed, which sound robotic. For a natural voice, download a Premium or Enhanced one in Settings → Accessibility → Read & Speak → Voices. It appears here once downloaded.")
                .font(.footnote)
                .foregroundStyle(hasNaturalVoice ? Theme.secondaryText : Theme.text.opacity(0.85))
        }
        .padding(20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private func voiceRow(title: String, detail: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.bold))
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func preview(_ voice: AVSpeechSynthesisVoice?) {
        guard let voice else { return }
        let cues = previewCues ?? SoundCueService()
        previewCues = cues
        cues.preview(voice)
    }

    private static func voiceDetail(_ voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch voice.quality {
        case .premium: quality = "Premium"
        case .enhanced: quality = "Enhanced"
        default: quality = "Basic"
        }
        let region = voice.language.split(separator: "-").last
            .flatMap { Locale.current.localizedString(forRegionCode: String($0)) }
        return [quality, region].compactMap { $0 }.joined(separator: " · ")
    }

    private func principle(_ systemImage: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.bold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.text.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private func linkRow(title: String, subtitle: String, systemImage: String, url: URL?) -> some View {
        let content = HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title3.weight(.bold))
                .foregroundStyle(url == nil ? Theme.secondaryText : Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline.weight(.bold))
                Text(url == nil ? "Coming soon" : subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            if url != nil {
                Image(systemName: "arrow.up.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))

        if let url {
            Link(destination: url) { content }
                .buttonStyle(.plain)
        } else {
            content.opacity(0.7)
        }
    }
}

#Preview {
    AboutView()
}
