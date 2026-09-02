import Foundation

/// One rate-limit window, e.g. a rolling 5-hour session or a weekly cap.
struct UsageWindow: Equatable, Identifiable {
    /// Stable identifier within one provider, e.g. "session" or "weekly".
    let id: String
    /// Short display label, e.g. "5h", "Weekly", "Fable".
    var label: String
    /// Length of the rolling window. Feeds the burn-rate projection: elapsed
    /// time is derived from the reset time and this.
    var duration: TimeInterval
    /// Fraction of the window already used, clamped to 0...1 by providers.
    var usedFraction: Double
    /// When the window resets, if the provider reports it.
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

    /// Label for a window known only by its length. Which windows exist is
    /// decided server-side per plan (Codex plans variously get 5h+weekly,
    /// weekly only, or monthly), so this mirrors the Codex CLI: match the
    /// known window lengths with ±5% tolerance, fall back to the raw length.
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

/// Everything Notchlet knows about one agent's limits at a point in time.
struct UsageSnapshot: Equatable {
    var windows: [UsageWindow]
    var fetchedAt: Date
    /// Plan tier ("plus", "max", ...) when the endpoint exposes one. Only
    /// used for anonymous analytics breakdowns, never shown in the UI.
    var planTier: String?
    /// Which of the provider's auth options produced this snapshot, for the
    /// status line on its settings page.
    var authOptionID: String?

    /// What a provider's summary gauge shows: the shortest window, because
    /// that is the one that runs out in normal use (the 5h session when the
    /// plan has one, else the plan's only window). Static per plan, never
    /// swayed by which window currently has the lowest percentage. Among
    /// windows of equal length the first wins, so providers whose windows
    /// all share one cycle put the headline first.
    var primaryWindow: UsageWindow? {
        windows.min { $0.duration < $1.duration }
    }
}

/// Date parsing shared by providers.
enum UsageDate {
    /// ISO 8601 with any fractional-second precision. `ISO8601DateFormatter`
    /// refuses fractions unless they are exactly three digits, and endpoints
    /// send three (Cursor) or six (Anthropic). Sub-second precision is
    /// irrelevant here, so the fraction is stripped before parsing.
    static func parse(_ string: String) -> Date? {
        let stripped = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: stripped)
    }
}
