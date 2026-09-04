import Foundation

/// What the scanner remembers between launches: every finding with its
/// status, and when each provider was last scanned. Previews and hashes
/// only, never a secret.
nonisolated struct SecretScanState: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = Self.currentVersion
    var findings: [SecretFinding] = []
    /// Stamped at the start of a scan, so a file that grows while the scan
    /// runs is picked up by the next one.
    var lastScanAt: [String: Date] = [:]
}

/// One JSON file under Application Support, written atomically.
nonisolated struct SecretStateStore: Sendable {
    static let `default` = SecretStateStore(
        url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Notchlet/Secrets/findings.json")
    )

    let url: URL

    /// Nil when there is no file yet or it is not the current version: a
    /// corrupt or foreign file starts over rather than crashing every launch.
    func load() -> SecretScanState? {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(SecretScanState.self, from: data),
              state.version == SecretScanState.currentVersion
        else { return nil }
        return state
    }

    func save(_ state: SecretScanState) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
