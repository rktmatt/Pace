import Foundation

/// Number formatting shared by the iPhone and Watch apps.
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
