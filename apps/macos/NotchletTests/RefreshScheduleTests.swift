import Foundation
@testable import Notchlet
import Testing

struct RefreshScheduleTests {
    private let start = Date(timeIntervalSince1970: 1_787_990_000)

    @Test func neverFetchedIsDueImmediately() {
        #expect(RefreshSchedule().nextDue(interval: 600) == .distantPast)
    }

    @Test func successFollowsTheAmbientInterval() {
        var schedule = RefreshSchedule()
        schedule.recordAttempt(now: start)
        schedule.recordSuccess()
        #expect(schedule.nextDue(interval: 600) == start.addingTimeInterval(600))
        // Opening the panel shrinks the interval, pulling the fetch forward.
        #expect(schedule.nextDue(interval: 60) == start.addingTimeInterval(60))
    }

    @Test func minimumSpacingAlwaysHolds() {
        var schedule = RefreshSchedule()
        schedule.recordAttempt(now: start)
        schedule.recordSuccess()
        #expect(schedule.nextDue(interval: 5) == start.addingTimeInterval(30))
    }

    @Test func retryAfterOnlyLengthensTheBackoff() {
        var schedule = RefreshSchedule()
        schedule.recordAttempt(now: start)
        // Anthropic's `retry-after: 0` must not mean "retry in 30s".
        schedule.recordRateLimit(retryAfter: 0, now: start)
        let first = schedule.nextDue(interval: 60).timeIntervalSince(start)
        #expect(first >= 300 && first <= 330)
        #expect(schedule.isRateLimited)

        schedule.recordRateLimit(retryAfter: 2400, now: start)
        #expect(schedule.nextDue(interval: 60) == start.addingTimeInterval(2400))

        schedule.recordRateLimit(retryAfter: 100_000, now: start)
        #expect(schedule.nextDue(interval: 60) == start.addingTimeInterval(3600))
    }

    @Test func theProviderFloorHoldsOverErrorRetries() {
        var schedule = RefreshSchedule()
        schedule.recordAttempt(now: start)
        schedule.recordError(now: start)
        #expect(schedule.nextDue(interval: 60, floor: 300) == start.addingTimeInterval(300))
        schedule.connectionRestored()
        #expect(schedule.nextDue(interval: 60, floor: 300) == start.addingTimeInterval(300))
    }

    @Test func retryNowKeepsARateLimit() {
        var schedule = RefreshSchedule()
        schedule.recordAttempt(now: start)
        schedule.recordError(now: start)
        schedule.retryNow()
        #expect(schedule.nextDue(interval: 600) == .distantPast)

        schedule.recordAttempt(now: start)
        schedule.recordRateLimit(retryAfter: nil, now: start)
        schedule.retryNow()
        #expect(schedule.nextDue(interval: 600) > start.addingTimeInterval(299))
    }

    @Test func rateLimitBackoffEscalatesThenCaps() {
        var schedule = RefreshSchedule()
        schedule.recordAttempt(now: start)
        for step in [300.0, 600, 1200, 1800, 1800] {
            schedule.recordRateLimit(retryAfter: nil, now: start)
            let delay = schedule.nextDue(interval: 600).timeIntervalSince(start)
            // Jitter adds up to 30s on top of the step.
            #expect(delay >= step && delay <= step + 30)
        }
    }

    @Test func successClearsTheBackoff() {
        var schedule = RefreshSchedule()
        schedule.recordAttempt(now: start)
        schedule.recordRateLimit(retryAfter: nil, now: start)
        schedule.recordSuccess()
        #expect(!schedule.isRateLimited)
        #expect(schedule.nextDue(interval: 600) == start.addingTimeInterval(600))
    }

    @Test func networkErrorsBackOffAndReconnectRecoversWithoutIgnoringRateLimits() {
        var schedule = RefreshSchedule()
        schedule.recordAttempt(now: start)
        schedule.recordError(now: start)
        // The 2 minute retry beats even a long ambient interval.
        #expect(schedule.nextDue(interval: 600) == start.addingTimeInterval(120))
        #expect(!schedule.isRateLimited)
        for delay in [240.0, 480, 960, 1800, 1800] {
            schedule.recordError(now: start)
            #expect(schedule.nextDue(interval: 600) == start.addingTimeInterval(delay))
        }
        schedule.connectionRestored()
        #expect(schedule.nextDue(interval: 600) == start.addingTimeInterval(30))
        schedule.recordRateLimit(retryAfter: 900, now: start)
        schedule.connectionRestored()
        #expect(schedule.nextDue(interval: 600) == start.addingTimeInterval(900))
        schedule.recordSuccess()
        schedule.recordError(now: start)
        #expect(schedule.nextDue(interval: 600) == start.addingTimeInterval(120))
    }
}
