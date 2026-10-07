import Foundation

/// One provider's fetch timing: minimum spacing, escalating backoff after
/// rate limits and other failures. The ambient poll
/// interval comes from `UsageStore`; shrinking it when the panel opens is
/// what pulls stale providers forward. Codable so a relaunch keeps both the
/// spacing and a running cooldown.
struct RefreshSchedule: Codable {
    static let minSpacing: TimeInterval = 30
    static let errorRetryDelay: TimeInterval = 120
    /// Per consecutive 429 without a Retry-After.
    static let rateLimitDelays: [TimeInterval] = [300, 600, 1200, 1800]

    private(set) var lastAttemptAt: Date?
    /// Overrides the regular cadence.
    private(set) var retryAt: Date?
    private(set) var rateLimitStreak = 0
    private(set) var errorStreak = 0

    var isRateLimited: Bool { rateLimitStreak > 0 }

    /// `floor` is the provider's minimum spacing, held over error retries
    /// and a restored connection too.
    func nextDue(interval: TimeInterval, floor: TimeInterval = 0) -> Date {
        guard let lastAttemptAt else { return .distantPast }
        let scheduled = retryAt ?? lastAttemptAt.addingTimeInterval(interval)
        return max(scheduled, lastAttemptAt.addingTimeInterval(max(Self.minSpacing, floor)))
    }

    mutating func recordAttempt(now: Date = .now) {
        lastAttemptAt = now
    }

    mutating func recordSuccess() {
        retryAt = nil
        rateLimitStreak = 0
        errorStreak = 0
    }

    /// The delay escalates per consecutive 429, with jitter so providers
    /// don't sync up. Retry-After can only lengthen it, up to an hour:
    /// Anthropic sends `retry-after: 0` while refusing for hours, and
    /// retrying on that schedule is what keeps a token locked out.
    mutating func recordRateLimit(retryAfter: TimeInterval?, now: Date = .now) {
        errorStreak = 0
        let step = Self.rateLimitDelays[min(rateLimitStreak, Self.rateLimitDelays.count - 1)]
            + Double.random(in: 0 ... 30)
        let delay = max(step, min(retryAfter ?? 0, 3600))
        rateLimitStreak += 1
        retryAt = now.addingTimeInterval(delay)
    }

    mutating func recordError(now: Date = .now) {
        rateLimitStreak = 0
        errorStreak = min(errorStreak + 1, 5)
        retryAt = now.addingTimeInterval(min(Self.errorRetryDelay * pow(2, Double(errorStreak - 1)), 1800))
    }

    /// The user asked for fresh numbers. A running rate limit stays,
    /// since retrying into it only extends it.
    mutating func retryNow() {
        guard !isRateLimited else { return }
        self = RefreshSchedule()
    }

    mutating func connectionRestored() {
        guard errorStreak > 0 else { return }
        errorStreak = 0
        retryAt = .distantPast
    }
}
