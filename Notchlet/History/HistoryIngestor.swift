import Foundation

/// The sealed archive plus the live days, recomputed on every ingest.
nonisolated struct ProviderHistory: Equatable, Sendable {
    var archive: ProviderArchive
    var live: [DailyUsage]

    var rows: [DailyUsage] { archive.rows + live }
}

/// Asks a source for events, rolls them into days, seals the days that are
/// old enough into the archive and hands back the rest as live rows. One
/// ingest per provider at a time: the actor is reentrant across the wait
/// on the source, and two ingests racing to save could move
/// `sealedThrough` backwards.
actor HistoryIngestor {
    private let archives: HistoryArchiveStore
    private let calendar: Calendar
    private var loaded: [String: ProviderArchive] = [:]
    private var running: [String: Task<ProviderHistory, any Error>] = [:]

    init(archives: HistoryArchiveStore = .default, calendar: Calendar = .localGregorian) {
        self.archives = archives
        self.calendar = calendar
    }

    /// As last saved, without reading any log.
    func archive(for providerID: String) -> ProviderArchive? {
        if let archive = loaded[providerID] {
            return archive
        }
        let archive = archives.load(providerID)
        loaded[providerID] = archive
        return archive
    }

    func ingest(_ providerID: String, from source: any UsageHistorySource,
                now: Date = .now) async throws -> ProviderHistory
    {
        if let running = running[providerID] {
            return try await running.value
        }
        let task = Task { try await run(providerID, from: source, now: now) }
        running[providerID] = task
        defer { running[providerID] = nil }
        return try await task.value
    }

    private func run(_ providerID: String, from source: any UsageHistorySource,
                     now: Date) async throws -> ProviderHistory
    {
        var archive = archive(for: providerID) ?? ProviderArchive(providerID: providerID)
        let plan = SealPlan(sealedThrough: archive.sealedThrough, now: now, calendar: calendar)
        let events = try await source.events(since: plan.readSince)
        let rows = UsageRollup.daily(UsageRollup.deduplicated(events), providerID: providerID, calendar: calendar)

        let today = DayKey(now, calendar: calendar)
        if archive.coverageStart == nil {
            archive.coverageStart = min(rows.map(\.day).min() ?? today, today)
        }
        let sealedThrough = archive.sealedThrough
        let sealing = rows.filter { row in
            row.day <= plan.sealThrough && sealedThrough.map { $0 < row.day } ?? true
        }
        if !sealing.isEmpty || sealedThrough != plan.sealThrough {
            archive.rows += sealing
            archive.rows.sort {
                ($0.day, $0.model ?? "", $0.reportedCost == nil ? 0 : 1) < (
                    $1.day,
                    $1.model ?? "",
                    $1.reportedCost == nil ? 0 : 1
                )
            }
            archive.sealedThrough = plan.sealThrough
            try archives.save(archive)
            loaded[providerID] = archive
        }

        return ProviderHistory(archive: archive, live: rows.filter { $0.day > plan.sealThrough })
    }
}
