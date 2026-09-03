import Foundation
@testable import Notchlet
import Testing

struct HistoryIngestorTests {
    private final class StubSource: UsageHistorySource, @unchecked Sendable {
        var events: [UsageEvent] = []
        var requestedSince: [Date?] = []
        var error: Error?

        func events(since: Date?) async throws -> [UsageEvent] {
            requestedSince.append(since)
            if let error {
                throw error
            }
            return events
        }
    }

    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func event(_ iso: String, model: String = "m", output: Int = 1) -> UsageEvent {
        UsageEvent(model: model, timestamp: date(iso), tokens: TokenCount(output: output))
    }

    private func temporaryStore() -> HistoryArchiveStore {
        HistoryArchiveStore(directory: FileManager.default.temporaryDirectory
            .appending(path: "notchlet-ingest-\(UUID().uuidString)"))
    }

    @Test func firstIngestSealsOldDaysAndKeepsRecentOnesLive() async throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let source = StubSource()
        source.events = [
            event("2026-08-20T10:00:00Z"),
            event("2026-09-01T10:00:00Z"), event("2026-09-01T11:00:00Z"),
            event("2026-09-02T10:00:00Z"),
            event("2026-09-03T10:00:00Z"),
        ]
        let ingestor = HistoryIngestor(archives: store, calendar: utc)

        let history = try await ingestor.ingest("p", from: source, now: date("2026-09-03T15:00:00Z"))

        #expect(source.requestedSince == [nil])
        #expect(history.archive.coverageStart?.string == "2026-08-20")
        #expect(history.archive.sealedThrough?.string == "2026-09-01")
        #expect(history.archive.rows.map(\.day.string) == ["2026-08-20", "2026-09-01"])
        #expect(history.archive.rows[1].requests == 2)
        #expect(history.live.map(\.day.string) == ["2026-09-02", "2026-09-03"])
        #expect(store.load("p") == history.archive)
    }

    @Test func laterIngestsOnlySealWhatIsNewAndIgnoreSealedDays() async throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let source = StubSource()
        source.events = [event("2026-09-01T10:00:00Z"), event("2026-09-02T10:00:00Z")]
        let ingestor = HistoryIngestor(archives: store, calendar: utc)
        _ = try await ingestor.ingest("p", from: source, now: date("2026-09-03T15:00:00Z"))

        // Two days later the log still holds the sealed day, now with an
        // extra recording of it (a resumed session copying old lines).
        source.events = [
            event("2026-09-01T10:00:00Z", output: 500),
            event("2026-09-02T10:00:00Z"), event("2026-09-03T10:00:00Z"), event("2026-09-05T10:00:00Z"),
        ]
        let history = try await ingestor.ingest("p", from: source, now: date("2026-09-05T15:00:00Z"))

        #expect(source.requestedSince.last == date("2026-09-02T00:00:00Z"))
        #expect(history.archive.sealedThrough?.string == "2026-09-03")
        #expect(history.archive.rows.map(\.day.string) == ["2026-09-01", "2026-09-02", "2026-09-03"])
        #expect(history.archive.rows[0].tokens.output == 1)
        #expect(history.live.map(\.day.string) == ["2026-09-05"])
        #expect(history.archive.coverageStart?.string == "2026-09-01")
    }

    @Test func anEmptyFirstIngestStartsCoverageToday() async throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let ingestor = HistoryIngestor(archives: store, calendar: utc)

        let history = try await ingestor.ingest("p", from: StubSource(), now: date("2026-09-03T15:00:00Z"))

        #expect(history.archive.coverageStart?.string == "2026-09-03")
        #expect(history.archive.sealedThrough?.string == "2026-09-01")
        #expect(history.rows.isEmpty)
    }

    @Test func aFailingSourceLeavesTheArchiveAlone() async throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let source = StubSource()
        source.events = [event("2026-08-20T10:00:00Z")]
        let ingestor = HistoryIngestor(archives: store, calendar: utc)
        let before = try await ingestor.ingest("p", from: source, now: date("2026-09-03T15:00:00Z"))

        source.error = CocoaError(.fileReadNoPermission)
        await #expect(throws: CocoaError.self) {
            try await ingestor.ingest("p", from: source, now: date("2026-09-10T15:00:00Z"))
        }
        #expect(await ingestor.archive(for: "p") == before.archive)
        #expect(store.load("p") == before.archive)
    }
}
