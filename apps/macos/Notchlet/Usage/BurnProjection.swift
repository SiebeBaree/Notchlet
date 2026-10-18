import Foundation

/// Does the window run out before it resets at the average burn since it
/// started? The same model CodexBar uses: rate = used / elapsed, elapsed
/// derived from the reset time and the window length.
struct BurnProjection: Equatable {
    enum Verdict: Equatable {
        case plenty
        case onPace
        case early
    }

    var verdict: Verdict
    /// Nil when usage is flat or still inside the grace period.
    var depletionDate: Date?

    /// Depletion inside 85% of the time to reset is early, past 115% is
    /// plenty.
    private static let onPaceBand = 0.85 ... 1.15
    /// Right after a reset a tiny burst extrapolates to "empty in minutes",
    /// so no run-out is claimed before this much of the window has elapsed
    /// (24 minutes of a 5-hour window). CodexBar's gate.
    private static let graceElapsedFraction = 0.08
    private static let freshUsedFraction = 0.005

    /// Nil when the reset time is missing or already past.
    static func project(_ window: UsageWindow, now: Date = .now) -> BurnProjection? {
        project(
            usedFraction: window.usedFraction,
            resetsAt: window.resetsAt,
            windowDuration: window.duration,
            now: now
        )
    }

    static func project(
        usedFraction: Double,
        resetsAt: Date?,
        windowDuration: TimeInterval,
        now: Date = .now
    ) -> BurnProjection? {
        guard let resetsAt, resetsAt > now else { return nil }
        let elapsed = windowDuration - resetsAt.timeIntervalSince(now)
        guard elapsed > 0 else { return nil }

        guard usedFraction >= freshUsedFraction, elapsed / windowDuration >= graceElapsedFraction else {
            return BurnProjection(verdict: .plenty, depletionDate: nil)
        }

        let rate = usedFraction / elapsed
        let depletion = now.addingTimeInterval((1 - usedFraction) / rate)
        let ratio = depletion.timeIntervalSince(now) / resetsAt.timeIntervalSince(now)
        let verdict: Verdict = if ratio < onPaceBand.lowerBound {
            .early
        } else if ratio > onPaceBand.upperBound {
            .plenty
        } else {
            .onPace
        }
        return BurnProjection(verdict: verdict, depletionDate: depletion)
    }
}
