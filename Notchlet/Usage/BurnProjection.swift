import Foundation

/// Answers "if usage continues at this pace, does the window run out before it
/// resets?" using the average burn rate since the window started, the same
/// model CodexBar uses: rate = used / elapsed, with elapsed derived from the
/// reset time and the window length. Stateless and AppKit-free.
struct BurnProjection: Equatable {
    enum Verdict: Equatable {
        /// Usage is flat, the window barely started, or projected depletion
        /// lands comfortably after the reset.
        case plenty
        /// Projected depletion lands near the reset.
        case onPace
        /// Projected depletion lands clearly before the reset.
        case early
    }

    var verdict: Verdict
    /// When the window is projected to hit 100%. Nil when usage is flat or
    /// still inside the grace period.
    var depletionDate: Date?

    /// Depletion inside 85% of the time to reset counts as early, past 115%
    /// as plenty. The band between reads as "empty around the reset".
    private static let onPaceBand = 0.85 ... 1.15
    /// Right after a reset a tiny burst extrapolates to "empty in minutes",
    /// so no run-out is claimed until this much of the window has elapsed
    /// (24 minutes of a 5-hour window). Mirrors CodexBar's gate.
    private static let graceElapsedFraction = 0.08
    /// Below this used fraction the window counts as untouched.
    private static let freshUsedFraction = 0.005

    /// Nil when the reset time is missing or already past (stale data).
    static func project(_ window: UsageWindow, now: Date = .now) -> BurnProjection? {
        project(
            usedFraction: window.usedFraction,
            resetsAt: window.resetsAt,
            windowDuration: window.duration,
            now: now
        )
    }

    /// Nil when the reset time is missing or already past (stale data).
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
