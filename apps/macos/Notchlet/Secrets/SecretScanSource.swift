import Foundation

/// Where one provider keeps its chats, for the secret scanner.
nonisolated protocol SecretScanSource: Sendable {
    /// Files last written on or after `since` (nil means everything), or,
    /// for a CLI that keeps chats in a database, rows to pipe in.
    func input(since: Date?) async throws -> SecretScanInput
}

nonisolated enum SecretScanInput: Sendable {
    case files([URL])
    case text(Data)

    var isEmpty: Bool {
        switch self {
        case let .files(urls): urls.isEmpty
        case let .text(data): data.isEmpty
        }
    }

    /// A whole file is rescanned when any of it changed; `merge` folds
    /// repeats of a known secret away.
    static func files(under roots: [URL], withExtension ext: String, modifiedSince since: Date?) -> [URL] {
        LogFiles.list(under: roots, withExtension: ext, modifiedSince: since).map(\.url)
    }
}
