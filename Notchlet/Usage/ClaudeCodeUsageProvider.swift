import Foundation

/// Usage for Claude Code.
///
/// Planned data source: the OAuth usage endpoint Claude Code itself calls to
/// render `/usage` (5-hour and weekly windows, with reset times). Credentials
/// live in the macOS keychain or `~/.claude/.credentials.json` depending on
/// how the user logged in.
struct ClaudeCodeUsageProvider: UsageProvider {
    let id = "claude-code"
    let name = "Claude Code"

    func fetchUsage() async throws -> UsageSnapshot {
        throw UsageProviderError.notImplemented
    }
}
