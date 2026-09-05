import Foundation

/// Where one provider keeps its chats, for the secret scanner.
///
/// A provider hands one of these out through `UsageProvider.secrets`, the
/// way it hands out a history source. The scanner asks for what changed
/// since its last pass and feeds that to the bundled betterleaks; the
/// source only knows where the CLI writes and in what shape.
nonisolated protocol SecretScanSource: Sendable {
    /// What to scan: files last written on or after `since` (nil means
    /// everything), or, for a CLI that keeps chats in a database, one row
    /// per line to pipe in.
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

    /// The files `LogFiles.list` finds. A whole file is rescanned when any
    /// of it changed; `SecretFinding.merge` folds repeats of a known secret
    /// away, so that costs a few seconds of a background core and nothing
    /// the user sees.
    static func files(under roots: [URL], withExtension ext: String, modifiedSince since: Date?) -> [URL] {
        LogFiles.list(under: roots, withExtension: ext, modifiedSince: since).map(\.url)
    }
}
