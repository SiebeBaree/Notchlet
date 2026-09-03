import Foundation
@testable import Notchlet
import Testing

struct HistoryModelsTests {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test func tokenCountSumsEveryBucket() {
        let a = TokenCount(input: 1, cacheRead: 10, cacheWrite5m: 100, cacheWrite1h: 1000, output: 10000)
        let b = TokenCount(input: 1, output: 1)
        #expect((a + b).promptTokens == 1112)
        #expect((a + b).total == 11113)
    }

    @Test func dayKeyRoundTripsAndCompares() throws {
        let day = try #require(DayKey("2026-09-03"))
        #expect(day.string == "2026-09-03")
        #expect(day < DayKey(year: 2026, month: 9, day: 4))
        #expect(day < DayKey(year: 2026, month: 10, day: 1))
        #expect(day > DayKey(year: 2025, month: 12, day: 31))
        #expect(DayKey("2026-13-01") == nil)
        #expect(DayKey("yesterday") == nil)
    }

    @Test func dayKeyBucketsInTheGivenCalendar() throws {
        var brussels = Calendar(identifier: .gregorian)
        brussels.timeZone = try #require(TimeZone(identifier: "Europe/Brussels"))
        let lateEvening = date("2026-09-03T22:30:00Z")
        #expect(DayKey(lateEvening, calendar: utc).string == "2026-09-03")
        #expect(DayKey(lateEvening, calendar: brussels).string == "2026-09-04")
    }

    @Test func dayKeyWalksAcrossMonths() {
        let day = DayKey(year: 2026, month: 3, day: 1)
        #expect(day.advanced(by: -1, calendar: utc).string == "2026-02-28")
        #expect(day.advanced(by: 31, calendar: utc).string == "2026-04-01")
        #expect(day.days(through: day.advanced(by: 2, calendar: utc), calendar: utc).map(\.string)
            == ["2026-03-01", "2026-03-02", "2026-03-03"])
        #expect(day.days(through: day.advanced(by: -1, calendar: utc), calendar: utc).isEmpty)
    }

    @Test func dayKeyEncodesAsAString() throws {
        let encoded = try JSONEncoder().encode([DayKey(year: 2026, month: 1, day: 9)])
        #expect(String(decoding: encoded, as: UTF8.self) == #"["2026-01-09"]"#)
        let decoded = try JSONDecoder().decode([DayKey].self, from: encoded)
        #expect(decoded == [DayKey(year: 2026, month: 1, day: 9)])
    }

    @Test func deduplicationKeepsTheFullestRecording() {
        let stamp = date("2026-09-03T10:00:00Z")
        let events = [
            UsageEvent(id: "msg_1", model: "m", timestamp: stamp, tokens: TokenCount(output: 5)),
            UsageEvent(id: "msg_1", model: "m", timestamp: stamp, tokens: TokenCount(output: 9)),
            UsageEvent(id: "msg_1", model: "m", timestamp: stamp, tokens: TokenCount(output: 9)),
            UsageEvent(id: nil, model: "m", timestamp: stamp, tokens: TokenCount(output: 1)),
            UsageEvent(id: nil, model: "m", timestamp: stamp, tokens: TokenCount(output: 1)),
        ]
        let kept = UsageRollup.deduplicated(events)
        #expect(kept.count == 3)
        #expect(kept.map(\.tokens.output).sorted() == [1, 1, 9])
    }

    @Test func rollupBucketsByDayAndModel() {
        let events = [
            UsageEvent(model: "opus", timestamp: date("2026-09-03T01:00:00Z"), tokens: TokenCount(input: 1, output: 2)),
            UsageEvent(model: "opus", timestamp: date("2026-09-03T23:00:00Z"), tokens: TokenCount(input: 3, output: 4)),
            UsageEvent(
                model: "haiku",
                timestamp: date("2026-09-03T12:00:00Z"),
                tokens: TokenCount(output: 1),
                reportedCost: 0.5
            ),
            UsageEvent(model: "opus", timestamp: date("2026-09-04T00:00:00Z"), tokens: TokenCount(output: 7)),
        ]
        let rows = UsageRollup.daily(events, providerID: "p", calendar: utc)

        #expect(rows.map { "\($0.day.string) \($0.model!)" } == [
            "2026-09-03 haiku",
            "2026-09-03 opus",
            "2026-09-04 opus",
        ])
        #expect(rows[1].requests == 2)
        #expect(rows[1].tokens == TokenCount(input: 4, output: 6))
        #expect(rows[1].reportedCost == nil)
        #expect(rows[0].reportedCost == 0.5)
        #expect(rows.allSatisfy { $0.providerID == "p" })
    }
}
