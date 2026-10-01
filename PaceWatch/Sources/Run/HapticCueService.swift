import WatchKit

/// The Watch's run cues: distinct taps on the wrist, so a switch is felt
/// without looking. Same moments as the phone's sound cues — a 3-2-1 click
/// before every switch, then "start" for more effort, "stop" to ease off.
@MainActor
final class HapticCueService: RunCueing {
    private let device = WKInterfaceDevice.current()

    func announce(transitionTo interval: IntervalDefinition, isLastRun: Bool, halfwayRemaining: Int?) {
        play(for: interval.kind)
    }

    func announceHalfway(remainingSeconds: Int) {
        device.play(.notification)
    }

    func announceMinutesLeft(_ minutes: Int) {
        device.play(.directionDown)
    }

    func announce(switchTo kind: IntervalKind) {
        play(for: kind)
    }

    func countdownTick() {
        device.play(.click)
    }

    func announcePause() {
        device.play(.stop)
    }

    func announceResume() {
        device.play(.start)
    }

    func announceCompletion(runningSeconds: Int) {
        device.play(.success)
    }

    private func play(for kind: IntervalKind) {
        switch kind {
        case .run, .warmup: device.play(.start)
        case .walk, .cooldown: device.play(.stop)
        }
    }
}
