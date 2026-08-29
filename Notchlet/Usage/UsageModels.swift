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

    /// The window closest to running out; what a provider's summary gauge
    /// shows.
    var tightestWindow: UsageWindow? {
        windows.min { $0.remainingFraction < $1.remainingFraction }
    }
}
