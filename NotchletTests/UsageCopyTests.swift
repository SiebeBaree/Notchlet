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

    @Test func shortDurationNeverSaysZero() {
        #expect(UsageCopy.shortDuration(20) == "1m")
    }

    @Test func shortDurationUsesDaysPastACalendarDay() {
        #expect(UsageCopy.shortDuration(112 * 3600 + 46 * 60) == "4d 16h")
        #expect(UsageCopy.shortDuration(48 * 3600) == "2d")
        #expect(UsageCopy.shortDuration(23 * 3600) == "23h")
    }
}
