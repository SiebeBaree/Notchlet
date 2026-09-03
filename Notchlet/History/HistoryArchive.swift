import Foundation

/// What Notchlet remembers for one provider once the CLI's own logs may be
/// gone: the days that are final, and the edges of what it can vouch for.
nonisolated struct ProviderArchive: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = Self.currentVersion
    var providerID: String
    /// The first day the archive can speak for: the older of the earliest
    /// day the logs reached at the first ingest and that ingest's day. Days
    /// before it are unknown, not zero.
    var coverageStart: DayKey?
    /// The last sealed day. Sealed days are contiguous, so a day with no
    /// usage seals as no rows rather than as a gap to revisit.
    var sealedThrough: DayKey?
    var rows: [DailyUsage] = []

    init(providerID: String) {
        self.providerID = providerID
    }
}

/// The archive files on disk, one JSON file per provider under Application
/// Support, written atomically. A year is about 1500 rows, so a file is read
/// once at launch and rewritten once per sealed day.
nonisolated struct HistoryArchiveStore: Sendable {
    static let `default` = HistoryArchiveStore(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Notchlet/History")
    )

    let directory: URL

    /// Nil when there is no file yet, or when it cannot be read as the
    /// current version: a corrupt or foreign file starts the provider over
    /// rather than crashing the app on every launch.
    func load(_ providerID: String) -> ProviderArchive? {
        guard let data = try? Data(contentsOf: url(for: providerID)),
              let archive = try? JSONDecoder().decode(ProviderArchive.self, from: data),
              archive.version == ProviderArchive.currentVersion
        else { return nil }
        return archive
    }

    func save(_ archive: ProviderArchive) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(archive).write(to: url(for: archive.providerID), options: .atomic)
    }

    private func url(for providerID: String) -> URL {
        directory.appending(path: "\(providerID).json")
    }
}

/// Which logs an ingest reads and which days it seals.
///
/// A day is live while it is today or yesterday: those are recomputed from
/// the logs every time and never stored. Nothing appends to an older day,
/// since every CLI writes the current time, so once a day falls out of the
/// live window it is rolled up once and sealed. The logs worth reading are
/// the ones written since the first unsealed day began: a file last touched
/// before that holds only sealed days.
nonisolated struct SealPlan: Equatable, Sendable {
    static let liveDays = 2

    /// Read logs modified on or after this; nil reads everything.
    let readSince: Date?
    /// Days up to and including this one are final after this ingest.
    let sealThrough: DayKey

    init(sealedThrough: DayKey?, now: Date, calendar: Calendar) {
        let today = DayKey(now, calendar: calendar)
        var sealThrough = today.advanced(by: -Self.liveDays, calendar: calendar)
        if let sealedThrough {
            readSince = sealedThrough.advanced(by: 1, calendar: calendar).start(in: calendar)
            // A clock or time zone that moved backwards never unseals.
            sealThrough = max(sealThrough, sealedThrough)
        } else {
            readSince = nil
        }
        self.sealThrough = sealThrough
    }
}
