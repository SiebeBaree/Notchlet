import Foundation

/// Every session and subagent JSONL under `~/.claude/projects`. Tool
/// results, where most leaks sit, are in the same lines as the messages.
nonisolated struct ClaudeCodeSecretSource: SecretScanSource {
    private let projectsDirectory: URL

    init(projectsDirectory: URL = ClaudeCodeHistorySource.defaultProjectsDirectory) {
        self.projectsDirectory = projectsDirectory
    }

    func input(since: Date?) async throws -> SecretScanInput {
        .files(SecretScanInput.files(under: [projectsDirectory], withExtension: "jsonl", modifiedSince: since))
    }
}
