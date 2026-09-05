import Foundation

/// One provider's fetch timing: minimum spacing, escalating backoff after
/// rate limits, a flat retry after other failures. The ambient poll
/// interval comes from `UsageStore`; shrinking it when the panel opens is
/// what pulls stale providers forward.
struct RefreshSchedule {
    static let minSpacing: TimeInterval = 30
    static let errorRetryDelay: TimeInterval = 120
    /// Per consecutive 429 without a Retry-After.
    static let rateLimitDelays: [TimeInterval] = [300, 600, 1200, 1800]

    private(set) var lastAttemptAt: Date?
    /// Overrides the regular cadence.
    private(set) var retryAt: Date?
    private(set) var rateLimitStreak = 0

    var isRateLimited: Bool { rateLimitStreak > 0 }

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

    /// Retry-After is honored within 30s...1h; without it the delay
    /// escalates per consecutive 429, with jitter so providers don't sync up.
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
