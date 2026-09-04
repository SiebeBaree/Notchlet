import Foundation
@testable import Notchlet
import Testing

struct UsageCopyTests {
    private let now = Date(timeIntervalSince1970: 1_787_990_000)

    @Test func resetWithinADayIsRelative() {
        #expect(UsageCopy.resetText(for: now.addingTimeInterval(51 * 60), now: now) == "Resets in 51m")
        #expect(UsageCopy.resetText(for: now.addingTimeInterval(3 * 3600 + 600), now: now) == "Resets in 3h 10m")
        #expect(UsageCopy.resetText(for: now.addingTimeInterval(2 * 3600), now: now) == "Resets in 2h")
    }

    @Test func resetBeyondADayNamesTheDay() {
        let text = UsageCopy.resetText(for: now.addingTimeInterval(5 * 24 * 3600), now: now)
        // Locale-dependent time format, so only pin the shape.
        #expect(text?.hasPrefix("Resets ") == true)
        #expect(text?.contains("in ") != true)
    }

    @Test func resetBeyondAWeekNamesTheDate() throws {
        let resetsAt = now.addingTimeInterval(30 * 24 * 3600)
        let text = try #require(UsageCopy.resetText(for: resetsAt, now: now))
        // A bare weekday is ambiguous a month out; expect the calendar date.
        let day = Calendar.current.component(.day, from: resetsAt)
        #expect(text.contains("\(day)"))
        #expect(!text.contains(":"))
    }

    @Test func missingResetGivesNoText() {
        #expect(UsageCopy.resetText(for: nil, now: now) == nil)
    }

    @Test func paceCopyPerVerdict() {
        let reset = now.addingTimeInterval(3600)
        #expect(UsageCopy.paceText(projection: nil, resetsAt: reset, now: now) == nil)
        #expect(
            UsageCopy.paceText(
                projection: BurnProjection(verdict: .plenty, depletionDate: nil),
                resetsAt: reset,
                now: now
            ) == "Plenty"
        )
        #expect(
            UsageCopy.paceText(
                projection: BurnProjection(verdict: .onPace, depletionDate: reset),
                resetsAt: reset,
                now: now
            ) == "On pace"
        )
        #expect(
            UsageCopy.paceText(
                projection: BurnProjection(verdict: .early, depletionDate: now.addingTimeInterval(1500)),
                resetsAt: reset,
                now: now
            ) == "Empty 35m early"
        )
    }

    @Test func freshDataShowsNoAgeLine() {
        #expect(UsageCopy.freshnessText(fetchedAt: now.addingTimeInterval(-90), now: now) == nil)
        #expect(UsageCopy.freshnessText(fetchedAt: nil, now: now) == nil)
    }

    @Test func staleDataNamesItsAge() {
        #expect(UsageCopy.freshnessText(fetchedAt: now.addingTimeInterval(-7 * 60), now: now) == "Updated 7m ago")
    }

    @Test func rateLimitCopyNamesProviderAndRetry() {
        #expect(
            UsageCopy.rateLimitText(providerName: "Claude", retryAt: now.addingTimeInterval(180), now: now)
                == "Claude rate limited, retrying in 3m"
        )
        #expect(
            UsageCopy.rateLimitText(providerName: "Claude", retryAt: now.addingTimeInterval(-5), now: now)
                == "Claude rate limited, retrying soon"
        )
    }

    @Test func shortDurationNeverSaysZero() {
        #expect(UsageCopy.shortDuration(20) == "1m")
    }

    @Test func shortDurationUsesDaysPastACalendarDay() {
        #expect(UsageCopy.shortDuration(112 * 3600 + 46 * 60) == "4d 16h")
        #expect(UsageCopy.shortDuration(48 * 3600) == "2d")
        #expect(UsageCopy.shortDuration(23 * 3600) == "23h")
    }

    @Test func providerStatusNamesTheOptionOrTheProblem() {
        let cli = AuthOption(id: "cli", label: "Codex CLI")
        let pasted = AuthOption(id: "key", label: "Pasted key", secretName: "API key")
        func status(_ state: UsageStore.ProviderState?, _ problem: AuthProblem? = nil, option: AuthOption? = nil,
                    retryAt: Date? = nil) -> String
        {
            UsageCopy.providerStatusText(
                state: state, problem: problem, option: option, signInHint: "Run codex login",
                retryAt: retryAt, now: now
            )
        }

        #expect(status(nil) == "Waiting for the first refresh")
        #expect(status(.ok, option: cli) == "Using Codex CLI")
        #expect(status(.ok, option: pasted) == "Using the pasted API key")
        #expect(status(.notAvailable, .signedOut) == "Not signed in. Run codex login.")
        #expect(status(.notAvailable, .expired) == "Login expired. Run codex login.")
        #expect(status(.notAvailable, .rejected) == "Login rejected. Run codex login.")
        #expect(status(.rateLimited, retryAt: now.addingTimeInterval(240)) == "Rate limited, retrying in 4m")
        #expect(status(.error, retryAt: now.addingTimeInterval(120)) == "Request failed, retrying in 2m")
        #expect(status(.error) == "Request failed, retrying soon")
    }

    @Test func alertHeadlineNamesTheWindowAndTheMark() {
        #expect(UsageCopy.alertHeadline(windowLabel: "5h", percent: 80) == "5h limit past 80%")
        #expect(UsageCopy.alertHeadline(windowLabel: "Weekly", percent: 100) == "Weekly limit used up")
    }
}
