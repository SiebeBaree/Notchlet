import Foundation

/// Per-provider fetch timing: minimum spacing between fetches, escalating
/// backoff after rate limits and a short flat retry after other failures.
/// Pure and clock-injected so the schedule math stays unit-testable.
///
/// The ambient poll interval (fast while the panel is open, the user's
/// setting while it is closed) lives in `UsageStore`; this type only answers
/// "when is this provider due next" given that interval. Shrinking the
/// interval when the panel opens is what pulls stale providers forward into
/// an immediate fetch.
struct RefreshSchedule {
    /// No trigger may fetch the same provider more often than this.
    static let minSpacing: TimeInterval = 30
    /// Flat retry after a network or server error, no escalation.
    static let errorRetryDelay: TimeInterval = 120
    /// Backoff per consecutive 429 when the response has no Retry-After.
    static let rateLimitDelays: [TimeInterval] = [300, 600, 1200, 1800]

    private(set) var lastAttemptAt: Date?
    /// Pending retry after a failure; overrides the regular cadence.
    private(set) var retryAt: Date?
    private(set) var rateLimitStreak = 0

    var isRateLimited: Bool { rateLimitStreak > 0 }

    /// When the next fetch is due given the ambient poll interval.
    func nextDue(interval: TimeInterval) -> Date {
        guard let lastAttemptAt else { return .distantPast }
        let scheduled = retryAt ?? lastAttemptAt.addingTimeInterval(interval)
        return max(scheduled, lastAttemptAt.addingTimeInterval(Self.minSpacing))
    }

    mutating func recordAttempt(now: Date = .now) {
        lastAttemptAt = now
    }

    mutating func recordSuccess() {
        retryAt = nil
        rateLimitStreak = 0
    }

    /// Retry-After is honored within 30s...1h; without it the delay escalates
    /// per consecutive 429, with jitter so providers don't sync up.
    mutating func recordRateLimit(retryAfter: TimeInterval?, now: Date = .now) {
        let delay: TimeInterval = if let retryAfter {
            min(max(retryAfter, Self.minSpacing), 3600)
        } else {
            Self.rateLimitDelays[min(rateLimitStreak, Self.rateLimitDelays.count - 1)]
                + Double.random(in: 0 ... 30)
        }
        rateLimitStreak += 1
        retryAt = now.addingTimeInterval(delay)
    }

    mutating func recordError(now: Date = .now) {
        rateLimitStreak = 0
        retryAt = now.addingTimeInterval(Self.errorRetryDelay)
    }
}
