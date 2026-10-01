import Foundation

/// Plays every cue through several channels at once — on the Watch, a tap on
/// the wrist plus the phone's own tones and spoken instructions.
@MainActor
final class CombinedCues: RunCueing {
    private let channels: [RunCueing]

    init(_ channels: [RunCueing]) {
        self.channels = channels
    }

    /// Haptics always; voice when the runner hasn't turned it off on Home.
    static func forWatch() -> CombinedCues {
        let voice = UserDefaults.standard.object(forKey: voiceCuesKey) as? Bool ?? true
        return CombinedCues(voice ? [HapticCueService(), SoundCueService()] : [HapticCueService()])
    }

    static let voiceCuesKey = "voiceCues"

    func announce(transitionTo interval: IntervalDefinition, isLastRun: Bool, halfwayRemaining: Int?) {
        channels.forEach { $0.announce(transitionTo: interval, isLastRun: isLastRun, halfwayRemaining: halfwayRemaining) }
    }

    func announceHalfway(remainingSeconds: Int) { channels.forEach { $0.announceHalfway(remainingSeconds: remainingSeconds) } }
    func announceMinutesLeft(_ minutes: Int) { channels.forEach { $0.announceMinutesLeft(minutes) } }
    func announce(switchTo kind: IntervalKind) { channels.forEach { $0.announce(switchTo: kind) } }
    func countdownTick() { channels.forEach { $0.countdownTick() } }
    func announcePause() { channels.forEach { $0.announcePause() } }
    func announceResume() { channels.forEach { $0.announceResume() } }
    func announceCompletion(runningSeconds: Int) { channels.forEach { $0.announceCompletion(runningSeconds: runningSeconds) } }
}
