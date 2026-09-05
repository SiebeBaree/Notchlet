import Foundation

/// One rate-limit window: a rolling 5-hour session, a weekly cap, a billing
/// cycle.
nonisolated struct UsageWindow: Codable, Equatable, Identifiable, Sendable {
    /// Stable within one provider, e.g. "session" or "weekly".
    let id: String
    var label: String
    var duration: TimeInterval
    /// Clamped to 0...1 by providers.
    var usedFraction: Double
    var resetsAt: Date?

    var remainingFraction: Double {
        min(max(1 - usedFraction, 0), 1)
    }

    /// Where the gauge should sit right now if usage were spread evenly over
    /// the window: 1 at the window start, 0 at the reset. Nil when the reset
    /// time is missing or already past (stale data).
    func expectedRemainingFraction(now: Date = .now) -> Double? {
        guard let resetsAt, resetsAt > now else { return nil }
        return min(max(resetsAt.timeIntervalSince(now) / duration, 0), 1)
    }

    /// Mirrors the Codex CLI, whose plans variously get 5h+weekly, weekly
    /// only or monthly: known lengths match with 5% tolerance, anything
    /// else reads as its raw length.
    static func label(forDuration duration: TimeInterval) -> String {
        let known: [(length: TimeInterval, label: String)] = [
            (5 * 3600, "5h"),
            (24 * 3600, "Daily"),
            (7 * 24 * 3600, "Weekly"),
            (30 * 24 * 3600, "Monthly"),
            (365 * 24 * 3600, "Annual"),
        ]
        if let match = known.first(where: { abs(duration - $0.length) <= $0.length * 0.05 }) {
            return match.label
        }
        return duration < 24 * 3600 ? "\(Int(duration / 3600))h" : "\(Int(duration / (24 * 3600)))d"
    }
}

struct UsageSnapshot: Equatable {
    var windows: [UsageWindow]
    var fetchedAt: Date
    /// Which auth option produced this snapshot, for the settings status
    /// line.
    var authOptionID: String?

    /// What the summary gauge shows: the shortest window, the one that runs
    /// out in normal use. Among equals the first wins, so a provider whose
    /// windows share one cycle lists the headline first.
    var primaryWindow: UsageWindow? {
        windows.min { $0.duration < $1.duration }
    }
}

nonisolated enum UsageDate {
    /// ISO 8601 with any fractional-second precision. `ISO8601DateFormatter`
    /// refuses fractions unless they are exactly three digits, and endpoints
    /// send three (Cursor) or six (Anthropic), so the fraction is stripped.
    /// Runs once per log line during an ingest, hence no regular expression
    /// and one shared formatter (documented thread-safe).
    static func parse(_ string: String) -> Date? {
        var stripped = string
        if let dot = stripped.firstIndex(of: ".") {
            let fractionEnd = stripped[stripped.index(after: dot)...].firstIndex { !$0.isNumber } ?? stripped.endIndex
            stripped.removeSubrange(dot ..< fractionEnd)
        }
        return formatter.date(from: stripped)
    }

    private nonisolated(unsafe) static let formatter = ISO8601DateFormatter()
}
