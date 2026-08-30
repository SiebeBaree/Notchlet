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

    @Test func retryAfterIsHonoredAndClamped() {
        var schedule = RefreshSchedule()
        schedule.recordAttempt(now: start)
        schedule.recordRateLimit(retryAfter: 90, now: start)
        #expect(schedule.nextDue(interval: 60) == start.addingTimeInterval(90))
        #expect(schedule.isRateLimited)

        schedule.recordRateLimit(retryAfter: 5, now: start)
        #expect(schedule.nextDue(interval: 60) == start.addingTimeInterval(30))

        schedule.recordRateLimit(retryAfter: 100_000, now: start)
        #expect(schedule.nextDue(interval: 60) == start.addingTimeInterval(3600))
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

    @Test func networkErrorRetriesQuicklyWithoutEscalating() {
        var schedule = RefreshSchedule()
        schedule.recordAttempt(now: start)
        schedule.recordError(now: start)
        // The 2 minute retry beats even a long ambient interval.
        #expect(schedule.nextDue(interval: 600) == start.addingTimeInterval(120))
        #expect(!schedule.isRateLimited)
    }
}
