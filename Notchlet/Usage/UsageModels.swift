import Foundation

/// One rate-limit window. Claude Code and Codex both expose a rolling 5-hour
/// window and a weekly window.
struct UsageWindow: Equatable {
    /// Fraction of the window already used, clamped to 0...1 by providers.
    var usedFraction: Double
    /// When the window resets, if the provider reports it.
    var resetsAt: Date?

    var remainingFraction: Double {
        min(max(1 - usedFraction, 0), 1)
    }
}

/// Everything Notchlet knows about one agent's limits at a point in time.
struct UsageSnapshot: Equatable {
    var fiveHour: UsageWindow?
    var weekly: UsageWindow?
    var fetchedAt: Date
}
