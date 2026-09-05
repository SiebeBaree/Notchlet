import Foundation

/// Every thread's JSONL under `~/.codex/sessions` and `archived_sessions`,
/// live copies first so an archived thread is not scanned twice.
nonisolated struct CodexSecretSource: SecretScanSource {
    private let roots: [URL]

    init(roots: [URL] = CodexHistorySource.defaultRoots) {
        self.roots = roots
    }

    func input(since: Date?) async throws -> SecretScanInput {
        .files(SecretScanInput.files(under: roots, withExtension: "jsonl", modifiedSince: since))
    }
}
