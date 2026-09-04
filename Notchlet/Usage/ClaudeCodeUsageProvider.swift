import Foundation
import os

/// Usage for Claude Code.
///
/// Reads the OAuth access token Claude Code stored at login (macOS keychain,
/// with `~/.claude/.credentials.json` as fallback) and calls the same usage
/// endpoint Claude Code's `/usage` screen calls. Claude Code rotates the
/// token every 8 hours while it runs, rewriting the keychain item each time;
/// see `CredentialSupport.keychainData` for why that read stays silent.
///
/// While Claude Code is idle the token simply expires, which used to leave
/// the notch stale until the next `claude` run. Now an expired token is
/// refreshed the way a second Claude Code process would do it, following
/// Claude Code's own lock and compare-and-swap protocol (see
/// `ClaudeCodeCredentialStore`), so Claude Code picks the new token up
/// instead of being signed out by it.
struct ClaudeCodeUsageProvider: HTTPUsageProvider {
    let id = "claude-code"
    let name = "Claude"
    let logoAssetName = "ClaudeLogo"
    let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    let signInHint = "Run claude to sign in"

    static let keychainOption = AuthOption(id: "keychain", label: "Claude Code")
    static let fileOption = AuthOption(id: "file", label: "Credentials file")
    let authOptions = [Self.keychainOption, Self.fileOption]
    let history: (any UsageHistorySource)? = ClaudeCodeHistorySource()
    let secrets: (any SecretScanSource)? = ClaudeCodeSecretSource()

    var isInstalled: Bool {
        CredentialSupport.homePathExists(".claude")
    }

    private static let sessionDuration: TimeInterval = 5 * 3600
    private static let weekDuration: TimeInterval = 7 * 24 * 3600

    private let store = ClaudeCodeCredentialStore()

    private struct Cached: Sendable {
        let optionID: String
        let credentials: ClaudeTokenRefresh.Credentials
    }

    /// The last credentials read, reused until they expire. The keychain
    /// read spawns a process and a token lasts hours, so reading once per
    /// token instead of once per refresh keeps the open panel's 60s cadence
    /// from forking `security` every minute. A rejected request clears this
    /// (see `HTTPUsageProvider.fetchUsage`) in case the server retired the
    /// old token when Claude Code rotated it.
    private let cache = OSAllocatedUnfairLock<Cached?>(initialState: nil)
    /// A refresh token the server already rejected. Trying it again every
    /// poll would only hammer the endpoint, so it is skipped until Claude
    /// Code stores a different one.
    private let deadRefreshToken = OSAllocatedUnfairLock<String?>(initialState: nil)

    func authHeaders(for option: AuthOption) async throws -> [String: String] {
        if let cached = cache.withLock({ $0 }), cached.optionID == option.id, !cached.credentials.isExpired() {
            return Self.headers(token: cached.credentials.accessToken)
        }
        let backend: ClaudeCodeCredentialStore.Backend = option.id == Self.fileOption.id ? .file : .keychain
        guard let stored = await store.read(backend),
              let credentials = ClaudeTokenRefresh.Credentials(json: stored.json)
        else {
            throw UsageProviderError.notAvailable(.signedOut)
        }
        let current = if credentials.isExpired() {
            try await refresh(backend, expired: credentials)
        } else {
            credentials
        }
        cache.withLock { $0 = Cached(optionID: option.id, credentials: current) }
        return Self.headers(token: current.accessToken)
    }

    /// Runs the refresh detached so a cancelled poll cannot abandon it
    /// halfway: once the server has rotated the token, the write-back has
    /// to happen or Claude Code is left with a dead refresh token.
    private func refresh(
        _ backend: ClaudeCodeCredentialStore.Backend,
        expired: ClaudeTokenRefresh.Credentials
    ) async throws -> ClaudeTokenRefresh.Credentials {
        if let dead = deadRefreshToken.withLock({ $0 }), dead == expired.refreshToken {
            throw UsageProviderError.notAvailable(.expired)
        }
        let store = store
        let outcome = await Task.detached { await store.refreshIfExpired(backend) }.value
        switch outcome {
        case let .current(credentials):
            return credentials
        case .noCredentials:
            throw UsageProviderError.notAvailable(.signedOut)
        case let .cannotRefresh(deadToken):
            deadRefreshToken.withLock { $0 = deadToken }
            throw UsageProviderError.notAvailable(.expired)
        case .lockBusy, .failed:
            throw UsageProviderError.requestFailed
        }
    }

    func forgetCredentials(for option: AuthOption) -> Bool {
        cache.withLock { cached in
            let hadCredentials = cached?.optionID == option.id
            cached = nil
            return hadCredentials
        }
    }

    private static func headers(token: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "anthropic-beta": "oauth-2025-04-20",
        ]
    }

    /// Maps the endpoint's `limits` array to usage windows: the rolling
    /// session, the weekly all-models window and any model-scoped weekly
    /// window (currently "Fable").
    func parseWindows(from data: Data) throws -> [UsageWindow] {
        struct Response: Decodable {
            struct Limit: Decodable {
                struct Scope: Decodable {
                    struct Model: Decodable { var displayName: String? }
                    var model: Model?
                }

                var kind: String
                var percent: Double
                var resetsAt: String?
                var scope: Scope?
            }

            var limits: [Limit]
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(Response.self, from: data)

        return response.limits.compactMap { limit in
            let resetsAt = limit.resetsAt.flatMap(UsageDate.parse)
            let usedFraction = min(max(limit.percent / 100, 0), 1)
            switch limit.kind {
            case "session":
                return UsageWindow(
                    id: "session",
                    label: UsageWindow.label(forDuration: Self.sessionDuration),
                    duration: Self.sessionDuration,
                    usedFraction: usedFraction,
                    resetsAt: resetsAt
                )
            case "weekly_all":
                return UsageWindow(
                    id: "weekly",
                    label: UsageWindow.label(forDuration: Self.weekDuration),
                    duration: Self.weekDuration,
                    usedFraction: usedFraction,
                    resetsAt: resetsAt
                )
            case "weekly_scoped":
                guard let model = limit.scope?.model?.displayName else { return nil }
                return UsageWindow(
                    id: "weekly-\(model.lowercased())",
                    label: model,
                    duration: Self.weekDuration,
                    usedFraction: usedFraction,
                    resetsAt: resetsAt
                )
            default:
                return nil
            }
        }
    }
}
