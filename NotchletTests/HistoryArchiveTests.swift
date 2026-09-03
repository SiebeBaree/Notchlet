import Foundation
@testable import Notchlet
import Testing

struct HistoryArchiveTests {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let now = ISO8601DateFormatter().date(from: "2026-09-03T15:00:00Z")!

    @Test func firstIngestReadsEverythingAndSealsThroughTheDayBeforeYesterday() {
        let plan = SealPlan(sealedThrough: nil, now: now, calendar: utc)
        #expect(plan.readSince == nil)
        #expect(plan.sealThrough.string == "2026-09-01")
    }

    @Test func laterIngestsReadFromTheFirstUnsealedDay() throws {
        let plan = try SealPlan(sealedThrough: #require(DayKey("2026-08-30")), now: now, calendar: utc)
        #expect(plan.readSince == ISO8601DateFormatter().date(from: "2026-08-31T00:00:00Z"))
        #expect(plan.sealThrough.string == "2026-09-01")
    }

    @Test func aClockThatMovedBackNeverUnseals() throws {
        let plan = try SealPlan(sealedThrough: #require(DayKey("2026-09-05")), now: now, calendar: utc)
        #expect(plan.sealThrough.string == "2026-09-05")
        #expect(plan.readSince == ISO8601DateFormatter().date(from: "2026-09-06T00:00:00Z"))
    }

    @Test func archivesRoundTripThroughDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "notchlet-archive-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryArchiveStore(directory: directory)
        var archive = ProviderArchive(providerID: "claude-code")
        archive.coverageStart = DayKey("2026-07-28")
        archive.sealedThrough = DayKey("2026-09-01")
        archive.rows = try [DailyUsage(
            day: #require(DayKey("2026-09-01")), providerID: "claude-code", model: "claude-opus-5",
            requests: 3, tokens: TokenCount(input: 1, cacheRead: 2, cacheWrite5m: 3, cacheWrite1h: 4, output: 5)
        )]

        #expect(store.load("claude-code") == nil)
        try store.save(archive)
        #expect(store.load("claude-code") == archive)
    }

    @Test func aForeignVersionStartsOver() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "notchlet-archive-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"version":99,"providerID":"codex","rows":[]}"#.utf8)
            .write(to: directory.appending(path: "codex.json"))
        try Data("nonsense".utf8).write(to: directory.appending(path: "cursor.json"))

        let store = HistoryArchiveStore(directory: directory)
        #expect(store.load("codex") == nil)
        #expect(store.load("cursor") == nil)
    }
}
