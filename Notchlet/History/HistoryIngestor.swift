import Foundation

/// One provider's history as the pane reads it: the sealed archive plus the
/// live days, recomputed from the logs on every ingest.
nonisolated struct ProviderHistory: Equatable, Sendable {
    var archive: ProviderArchive
    var live: [DailyUsage]

    var rows: [DailyUsage] { archive.rows + live }
}

/// Runs ingests off the main actor: asks a source for events, rolls them
/// into days, seals the days that are old enough into the archive on disk
/// and hands back the rest as live rows. Owns the archives so the store
/// never touches a file. One ingest per provider runs at a time; a call
/// that arrives while one is running gets that one's result, since the
/// actor is reentrant across the wait on the source and two ingests
/// racing to save could move `sealedThrough` backwards.
actor HistoryIngestor {
    private let archives: HistoryArchiveStore
    private let calendar: Calendar
    private var loaded: [String: ProviderArchive] = [:]
    private var running: [String: Task<ProviderHistory, any Error>] = [:]

    init(archives: HistoryArchiveStore = .default, calendar: Calendar = .localGregorian) {
        self.archives = archives
        self.calendar = calendar
    }

    /// The archive as last saved, without reading any log. What the pane
    /// shows at launch while the first ingest runs.
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
