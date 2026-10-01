import Foundation
import AVFoundation

/// Announces interval transitions with a short tone motif followed by a spoken
/// instruction, so a run can be followed without looking at the screen.
///
/// Tones are synthesized at launch rather than shipped as assets: one small
/// palette tuned around A major so every cue sounds like the same app. Rising
/// motifs mean "more effort", falling ones "ease off"; a 3-2-1 tick precedes
/// every switch so it never arrives as a surprise.
///
/// Everything plays through the app's own audio session (`.playback`), so cues
/// are heard with the silent switch on and with the phone locked. The session is
/// only active while a cue is sounding: music is ducked and podcasts paused for
/// those seconds, then handed back.
@MainActor
final class SoundCueService: NSObject, RunCueing {
    private let synthesizer = AVSpeechSynthesizer()
    /// Cue text is written in the app's UI language, so the voice must match it —
    /// not the device's system language, which would read English with a foreign accent.
    private let voice = SoundCueService.bestVoice(for: Bundle.main.preferredLocalizations.first ?? "en")
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let tones: [Tone: AVAudioPCMBuffer]
    private var pendingSpeech: DispatchWorkItem?
    private var pendingDeactivation: DispatchWorkItem?

    override init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: ToneSynth.sampleRate, channels: 1)!
        tones = Dictionary(uniqueKeysWithValues: Tone.allCases.compactMap { tone in
            ToneSynth.render(tone.notes, format: format).map { (tone, $0) }
        })
        super.init()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        synthesizer.delegate = self
        // Spoken cues should duck music and pause podcasts rather than stop them,
        // and keep playing with the screen locked or the silent switch on.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
    }

    // MARK: - Cues

    /// - Parameter isLastRun: the final run of a session with several, worth
    ///   naming because it's the one runners hold on for.
    /// - Parameter halfwayRemaining: set when this switch is also the session's
    ///   midpoint — said after the instruction, which stays the thing to act on.
    func announce(transitionTo interval: IntervalDefinition, isLastRun: Bool = false, halfwayRemaining: Int? = nil) {
        var text = "\(interval.kind.voicePrompt) for \(Self.durationPhrase(interval.durationSeconds))."
        if isLastRun { text += " Last one." }
        if let halfwayRemaining { text += " " + Self.halfwayPhrase(remainingSeconds: halfwayRemaining) }
        play(Tone(segment: interval.kind), thenSay: text)
    }

    /// The session's midpoint, when it falls inside an interval rather than on a
    /// switch. Names what's left rather than what's done: that's the half that
    /// still has to be run.
    func announceHalfway(remainingSeconds: Int) {
        play(.halfway, thenSay: Self.halfwayPhrase(remainingSeconds: remainingSeconds))
    }

    /// Each whole minute left in a long interval, so the runner can pace the
    /// rest of it without looking down.
    func announceMinutesLeft(_ minutes: Int) {
        play(.minute, thenSay: "\(Self.durationPhrase(minutes * 60)) left.")
    }

    /// Free run: the runner chose the switch, so just confirm the new effort.
    func announce(switchTo kind: IntervalKind) {
        play(Tone(segment: kind), thenSay: kind.voicePrompt)
    }

    /// One of the three ticks before a switch.
    func countdownTick() {
        play(.tick)
    }

    func announcePause() {
        play(.pause, thenSay: "Paused")
    }

    func announceResume() {
        play(.resume, thenSay: "Resumed")
    }

    /// Names the real number rather than cheering: the running time is what the
    /// session was for.
    func announceCompletion(runningSeconds: Int) {
        var text = "Session complete."
        if runningSeconds >= 60 {
            text += " \(Self.durationPhrase(runningSeconds)) of running today."
        }
        play(.complete, thenSay: text)
    }

    // MARK: - Playback

    private func play(_ tone: Tone, thenSay text: String? = nil) {
        activate()
        if let buffer = tones[tone], engine.isRunning {
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            player.play()
        }
        pendingSpeech?.cancel()
        pendingSpeech = nil
        guard let text else {
            scheduleDeactivation(after: tone.duration + 1.5)
            return
        }
        // A new instruction supersedes one still being read out.
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .word) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.postUtteranceDelay = 0.2
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSpeech = nil
            self?.synthesizer.speak(utterance)
        }
        pendingSpeech = work
        // Speak right as the motif rings out, so the two read as one cue.
        DispatchQueue.main.asyncAfter(deadline: .now() + tone.duration * 0.8, execute: work)
    }

    private func activate() {
        pendingDeactivation?.cancel()
        pendingDeactivation = nil
        try? AVAudioSession.sharedInstance().setActive(true)
        // The engine stops on interruptions (calls) and route changes (AirPods);
        // restarting lazily here recovers from both.
        if !engine.isRunning { try? engine.start() }
    }

    /// Hands audio back to music/podcasts once nothing is left to say. Delayed so
    /// a 3-2-1 countdown and its switch cue share one ducked stretch.
    private func scheduleDeactivation(after delay: TimeInterval) {
        pendingDeactivation?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pendingSpeech == nil, !self.synthesizer.isSpeaking else { return }
            self.pendingDeactivation = nil
            self.player.stop()
            self.engine.pause()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        pendingDeactivation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Wording

    /// Rounded to the half minute: "12 and a half minutes" carries the news,
    /// "12 minutes 37 seconds" just makes it harder to hear.
    static func halfwayPhrase(remainingSeconds: Int) -> String {
        let rounded = remainingSeconds >= 90 ? Int((Double(remainingSeconds) / 30).rounded()) * 30 : remainingSeconds
        return "Halfway there, \(durationPhrase(rounded)) to go."
    }

    static func durationPhrase(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let minutePart = "\(minutes) minute\(minutes == 1 ? "" : "s")"
        let secondPart = "\(seconds) seconds"
        switch (minutes, seconds) {
        case (0, _): return secondPart
        case (_, 0): return minutePart
        case (1, 30): return "a minute and a half"
        case (_, 30): return "\(minutes) and a half minutes"
        default: return "\(minutePart) \(secondPart)"
        }
    }

    /// Highest-quality installed voice for the language, preferring the user's
    /// own region variant (e.g. en-GB) when one exists, then en-US-style defaults.
    private static func bestVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(languageCode) && !$0.voiceTraits.contains(.isNoveltyVoice) }
        let userRegion = "\(languageCode)-\(Locale.current.region?.identifier ?? "")"
        let defaultRegion = AVSpeechSynthesisVoice(language: languageCode)?.language
        func rank(_ voice: AVSpeechSynthesisVoice) -> (Int, Int) {
            let region = voice.language == userRegion ? 2 : (voice.language == defaultRegion ? 1 : 0)
            return (voice.quality.rawValue, region)
        }
        return candidates.max { rank($0) < rank($1) } ?? AVSpeechSynthesisVoice(language: languageCode)
    }
}

extension SoundCueService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.scheduleDeactivation(after: 0.6) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.scheduleDeactivation(after: 1.5) }
    }
}

// MARK: - Tone palette

/// The app's sonic vocabulary. Pitches sit in A major (A, C♯, E) so any two
/// cues heard back to back stay consonant.
enum Tone: CaseIterable {
    case tick, minute, halfway, run, walk, warmup, cooldown, pause, resume, complete

    init(segment kind: IntervalKind) {
        switch kind {
        case .run: self = .run
        case .walk: self = .walk
        case .warmup: self = .warmup
        case .cooldown: self = .cooldown
        }
    }

    private static let a4 = 440.0, cs5 = 554.37, e5 = 659.26, a5 = 880.0
    private static let cs6 = 1108.73, e6 = 1318.51, a6 = 1760.0

    var notes: [ToneSynth.Note] {
        typealias N = ToneSynth.Note
        switch self {
        // Short, dry, high: a clock, not an alarm.
        case .tick:
            return [N(Self.e6, at: 0, length: 0.07, gain: 0.30, ring: 0.02)]
        // A single soft chime: information, not an instruction to change.
        case .minute:
            return [N(Self.cs6, at: 0, length: 0.35, gain: 0.28, ring: 0.12)]
        // Two chimes rising to the octave, softer than a switch: a landmark,
        // not a change of effort.
        case .halfway:
            return [N(Self.a5, at: 0, length: 0.16, gain: 0.30, ring: 0.1),
                    N(Self.a6, at: 0.15, length: 0.60, gain: 0.30, ring: 0.25)]
        // Up a fifth then the octave: brisk and bright — go.
        case .run:
            return [N(Self.a5, at: 0, length: 0.10, gain: 0.45),
                    N(Self.e6, at: 0.09, length: 0.10, gain: 0.45),
                    N(Self.a6, at: 0.18, length: 0.40, gain: 0.40, ring: 0.14)]
        // The same notes falling, slower and softer — settle.
        case .walk:
            return [N(Self.e6, at: 0, length: 0.16, gain: 0.35),
                    N(Self.a5, at: 0.15, length: 0.55, gain: 0.35, ring: 0.2)]
        case .warmup:
            return [N(Self.cs5, at: 0, length: 0.14, gain: 0.35),
                    N(Self.e5, at: 0.13, length: 0.55, gain: 0.35, ring: 0.2)]
        case .cooldown:
            return [N(Self.e5, at: 0, length: 0.18, gain: 0.32),
                    N(Self.cs5, at: 0.17, length: 0.25, gain: 0.30),
                    N(Self.a4, at: 0.40, length: 0.80, gain: 0.30, ring: 0.3)]
        // Low register, so they can't be mistaken for an interval switch.
        case .pause:
            return [N(Self.cs5, at: 0, length: 0.12, gain: 0.32),
                    N(Self.a4, at: 0.12, length: 0.35, gain: 0.32, ring: 0.12)]
        case .resume:
            return [N(Self.a4, at: 0, length: 0.12, gain: 0.32),
                    N(Self.cs5, at: 0.12, length: 0.35, gain: 0.32, ring: 0.12)]
        // A full arpeggio, the only cue allowed to linger.
        case .complete:
            return [N(Self.a5, at: 0, length: 0.14, gain: 0.30),
                    N(Self.cs6, at: 0.12, length: 0.14, gain: 0.30),
                    N(Self.e6, at: 0.24, length: 0.14, gain: 0.30),
                    N(Self.a6, at: 0.36, length: 1.20, gain: 0.32, ring: 0.45)]
        }
    }

    var duration: TimeInterval {
        notes.map { $0.start + $0.length }.max() ?? 0
    }
}

/// Renders note lists into PCM: a sine with a little 2nd/3rd harmonic for a
/// soft bell timbre, fast attack, exponential decay.
enum ToneSynth {
    static let sampleRate = 44_100.0

    struct Note {
        var frequency: Double
        var start: TimeInterval
        var length: TimeInterval
        var gain: Double
        /// Decay time constant; short = plucked, long = ringing.
        var ring: TimeInterval

        init(_ frequency: Double, at start: TimeInterval, length: TimeInterval, gain: Double, ring: TimeInterval = 0.05) {
            self.frequency = frequency
            self.start = start
            self.length = length
            self.gain = gain
            self.ring = ring
        }
    }

    static func render(_ notes: [Note], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let total = notes.map { $0.start + $0.length }.max() ?? 0
        let frameCount = AVAudioFrameCount((total * sampleRate).rounded(.up))
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount
        for i in 0..<Int(frameCount) { samples[i] = 0 }

        let attack = 0.004, release = 0.012
        for note in notes {
            let first = Int(note.start * sampleRate)
            let count = Int(note.length * sampleRate)
            for n in 0..<count where first + n < Int(frameCount) {
                let t = Double(n) / sampleRate
                var envelope = exp(-t / note.ring) * note.gain
                if t < attack { envelope *= t / attack }
                let tail = note.length - t
                if tail < release { envelope *= max(0, tail / release) }
                let phase = 2 * Double.pi * note.frequency * t
                let wave = sin(phase) + 0.22 * sin(2 * phase) + 0.06 * sin(3 * phase)
                samples[first + n] += Float(wave * envelope / 1.28)
            }
        }
        // Overlapping notes can sum past full scale; clip softly rather than wrap.
        for i in 0..<Int(frameCount) { samples[i] = Float(tanh(Double(samples[i]))) }
        return buffer
    }
}
