import Foundation

/// Usage for OpenAI Codex.
///
/// Planned data source: the rate-limit data the Codex CLI shows in `/status`
/// (5-hour and weekly windows). Auth state lives in `~/.codex/auth.json`.
struct CodexUsageProvider: UsageProvider {
    let id = "codex"
    let name = "Codex"

    func fetchUsage() async throws -> UsageSnapshot {
        throw UsageProviderError.notImplemented
    }
}
