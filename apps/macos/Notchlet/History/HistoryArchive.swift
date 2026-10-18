import Foundation

/// What Notchlet remembers for one provider once the CLI's own logs may be
/// gone.
nonisolated struct ProviderArchive: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = Self.currentVersion
    var providerID: String
    /// Days before this are unknown, not zero.
    var coverageStart: DayKey?
    /// Sealed days are contiguous: a day with no usage seals as no rows.
    var sealedThrough: DayKey?
    var rows: [DailyUsage] = []

    init(providerID: String) {
        self.providerID = providerID
    }
}

/// One JSON file per provider under Application Support. A year is about
/// 1500 rows.
nonisolated struct HistoryArchiveStore: Sendable {
    static let `default` = HistoryArchiveStore(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Notchlet/History")
    )

    let directory: URL

    /// A corrupt, foreign or misplaced file starts the provider over rather
    /// than crashing every launch.
    func load(_ providerID: String) -> ProviderArchive? {
        guard let data = try? Data(contentsOf: url(for: providerID)),
              let archive = try? JSONDecoder().decode(ProviderArchive.self, from: data),
              archive.version == ProviderArchive.currentVersion, archive.providerID == providerID
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

/// Today and yesterday are live, recomputed from the logs every time and
/// never stored; every CLI writes the current time, so an older day is
/// rolled up once and sealed. A file last touched before the first
/// unsealed day began holds only sealed days and is not read.
nonisolated struct SealPlan: Equatable, Sendable {
    static let liveDays = 2

    /// Nil reads everything.
    let readSince: Date?
    let sealThrough: DayKey

    init(sealedThrough: DayKey?, now: Date, calendar: Calendar) {
        let today = DayKey(now, calendar: calendar)
        var sealThrough = today.advanced(by: -Self.liveDays, calendar: calendar)
        if let sealedThrough {
            readSince = sealedThrough.advanced(by: 1, calendar: calendar).start(in: calendar)
            // A clock that moved backwards never unseals.
            sealThrough = max(sealThrough, sealedThrough)
        } else {
            readSince = nil
        }
        self.sealThrough = sealThrough
    }
}
