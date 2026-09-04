import Foundation

/// Claude Code's transcripts as a scan source: every session and subagent
/// JSONL under `~/.claude/projects`. Tool results are where most leaks sit,
/// a cat of an .env or a curl with a bearer header, and they are in the
/// same lines as the messages.
nonisolated struct ClaudeCodeSecretSource: SecretScanSource {
    private let projectsDirectory: URL

    init(projectsDirectory: URL = ClaudeCodeHistorySource.defaultProjectsDirectory) {
        self.projectsDirectory = projectsDirectory
    }

    func input(since: Date?) async throws -> SecretScanInput {
        .files(SecretScanInput.files(under: [projectsDirectory], withExtension: "jsonl", modifiedSince: since))
    }
}
