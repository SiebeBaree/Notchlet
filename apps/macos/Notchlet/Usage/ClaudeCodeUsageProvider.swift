import Foundation
import os

/// Reads the OAuth token Claude Code stored at login (keychain, with
/// `~/.claude/.credentials.json` as fallback, then the one Claude Desktop
/// keeps for its Code tab) and calls the endpoint behind its `/usage`
/// screen. Claude Code rotates the token every 8 hours while it runs; once
/// it has expired, Notchlet refreshes it the way a second Claude Code
/// process would (`ClaudeCodeCredentialStore`). Desktop's token is only
/// ever read (`ClaudeDesktopTokenCache`).
///
/// The endpoint locks a token out for hours once it is asked too often, and
/// Claude Code asks it too, so Notchlet asks at most every 5 minutes and
/// first takes the answer Claude Code saved in `~/.claude.json` when that
/// is recent.
struct ClaudeCodeUsageProvider: HTTPUsageProvider {
    let id = "claude-code"
    let name = "Claude"
    let logoAssetName = "ClaudeLogo"
    let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    let signInHint = "Run claude to sign in"
    let minimumInterval: TimeInterval = 5 * 60

    static let keychainOption = AuthOption(id: "keychain", label: "Claude Code")
    static let fileOption = AuthOption(id: "file", label: "Credentials file")
    static let desktopOption = AuthOption(id: "desktop", label: "Claude Desktop")
    let authOptions = [Self.keychainOption, Self.fileOption, Self.desktopOption]
    let history: (any UsageHistorySource)? = ClaudeCodeHistorySource()
    let secrets: (any SecretScanSource)? = ClaudeCodeSecretSource()

    var isInstalled: Bool {
        CredentialSupport.homePathExists(".claude") || ClaudeDesktopTokenCache.isPresent
    }

    private nonisolated static let sessionDuration: TimeInterval = 5 * 3600
    private nonisolated static let weekDuration: TimeInterval = 7 * 24 * 3600

    private let store = ClaudeCodeCredentialStore()
    private let desktop = ClaudeDesktopTokenCache.Reader()
    /// Where Claude Code keeps its settings beside the default config
    /// directory, the one `store` reads.
    private let configFileURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude.json")

    /// Claude Code's saved answer belongs to its own login, so it stands in
    /// only for the options that read that login.
    func fetchUsage() async throws -> UsageSnapshot {
        let selection = ProviderAuthSettings.selection(for: id, options: authOptions)
        if let option = selection.resolve(authOptions).first, option != Self.desktopOption,
           let data = try? Data(contentsOf: configFileURL),
           let saved = Self.savedUsage(fromConfig: data, authOptionID: option.id),
           saved.fetchedAt.timeIntervalSinceNow > -minimumInterval
        {
            return saved
        }
        return try await fetchFromEndpoint()
    }

    /// The `cachedUsageUtilization` Claude Code writes after each of its own
    /// usage requests, when it belongs to the account signed in there.
    nonisolated static func savedUsage(fromConfig data: Data, authOptionID: String) -> UsageSnapshot? {
        struct Config: Decodable {
            struct Account: Decodable {
                var accountUuid: String?
                var organizationType: String?
                var organizationRateLimitTier: String?
            }

            struct Saved: Decodable {
                var fetchedAtMs: Double
                var accountUuid: String?
                var utilization: UsageResponse
            }

            var oauthAccount: Account?
            var cachedUsageUtilization: Saved?
        }

        guard let config = try? decoder.decode(Config.self, from: data),
              let account = config.oauthAccount, let saved = config.cachedUsageUtilization,
              account.accountUuid != nil, saved.accountUuid == account.accountUuid
        else { return nil }
        let windows = windows(from: saved.utilization)
        guard !windows.isEmpty else { return nil }
        return UsageSnapshot(
            windows: windows,
            fetchedAt: Date(timeIntervalSince1970: saved.fetchedAtMs / 1000),
            authOptionID: authOptionID,
            // "claude_max" here is "max" in the credentials.
            plan: UsagePlan.claude(
                subscriptionType: account.organizationType.map { $0.replacingOccurrences(of: "claude_", with: "") },
                rateLimitTier: account.organizationRateLimitTier
            )
        )
    }

    private struct Cached: Sendable {
        let optionID: String
        let accessToken: String
        let expiresAt: Date
        /// Desktop's token says nothing about the plan.
        var plan: UsagePlan?
    }

    /// Reused until it expires: every option's read spawns a process and a
    /// token lasts hours. A rejected request clears it.
    private let cache = OSAllocatedUnfairLock<Cached?>(initialState: nil)
    /// A refresh token the server rejected, skipped until Claude Code
    /// stores a different one.
    private let deadRefreshToken = OSAllocatedUnfairLock<String?>(initialState: nil)

    func authHeaders(for option: AuthOption) async throws -> [String: String] {
        if let cached = cache.withLock({ $0 }), cached.optionID == option.id, cached.expiresAt > .now {
            return Self.headers(token: cached.accessToken)
        }
        if option.id == Self.desktopOption.id {
            guard let token = try await desktop.read() else {
                throw ProviderError.notAvailable(.signedOut)
            }
            guard token.expiresAt > .now else {
                throw ProviderError.notAvailable(.expired)
            }
            let fresh = Cached(optionID: option.id, accessToken: token.accessToken, expiresAt: token.expiresAt)
            cache.withLock { $0 = fresh }
            return Self.headers(token: token.accessToken)
        }
        let backend: ClaudeCodeCredentialStore.Backend = option.id == Self.fileOption.id ? .file : .keychain
        guard let stored = await store.read(backend),
              let credentials = ClaudeTokenRefresh.Credentials(json: stored.json)
        else {
            throw ProviderError.notAvailable(.signedOut)
        }
        let current = if credentials.isExpired() {
            try await refresh(backend, expired: credentials)
        } else {
            credentials
        }
        let fresh = Cached(
            optionID: option.id, accessToken: current.accessToken, expiresAt: current.expiresAt, plan: current.plan
        )
        cache.withLock { $0 = fresh }
        return Self.headers(token: current.accessToken)
    }

    /// The usage response never names the plan; the credentials do.
    func plan(from data: Data) -> UsagePlan? {
        cache.withLock { $0?.plan }
    }

    /// Detached so a cancelled poll cannot abandon it halfway: once the
    /// server has rotated the token, the write-back has to happen or Claude
    /// Code is left with a dead refresh token.
    private func refresh(
        _ backend: ClaudeCodeCredentialStore.Backend,
        expired: ClaudeTokenRefresh.Credentials
    ) async throws -> ClaudeTokenRefresh.Credentials {
        if let dead = deadRefreshToken.withLock({ $0 }), dead == expired.refreshToken {
            throw ProviderError.notAvailable(.expired)
        }
        let store = store
        let outcome = await Task.detached { await store.refreshIfExpired(backend) }.value
        switch outcome {
        case let .current(credentials):
            return credentials
        case .noCredentials:
            throw ProviderError.notAvailable(.signedOut)
        case let .cannotRefresh(deadToken):
            deadRefreshToken.withLock { $0 = deadToken }
            throw ProviderError.notAvailable(.expired)
        case .lockBusy, .failed:
            throw ProviderError.requestFailed
        }
    }

    func retryCredentialAccess() {
        desktop.retryAccess()
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

    func parseWindows(from data: Data) throws -> [UsageWindow] {
        try Self.windows(from: Self.decoder.decode(UsageResponse.self, from: data))
    }

    /// Camel-case keys pass through untouched, so `~/.claude.json` decodes
    /// with it too.
    private nonisolated static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// The usage response, as the endpoint sends it and as Claude Code saves it.
    private nonisolated struct UsageResponse: Decodable {
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

    /// The rolling session, the weekly all-models window and any
    /// model-scoped weekly window.
    private nonisolated static func windows(from response: UsageResponse) -> [UsageWindow] {
        response.limits.compactMap { limit in
            let resetsAt = limit.resetsAt.flatMap(UsageDate.parse)
            let usedFraction = min(max(limit.percent / 100, 0), 1)
            switch limit.kind {
            case "session":
                return UsageWindow(
                    id: "session",
                    label: UsageWindow.label(forDuration: sessionDuration),
                    duration: sessionDuration,
                    usedFraction: usedFraction,
                    resetsAt: resetsAt
                )
            case "weekly_all":
                return UsageWindow(
                    id: "weekly",
                    label: UsageWindow.label(forDuration: weekDuration),
                    duration: weekDuration,
                    usedFraction: usedFraction,
                    resetsAt: resetsAt
                )
            case "weekly_scoped":
                guard let model = limit.scope?.model?.displayName else { return nil }
                return UsageWindow(
                    id: "weekly-\(model.lowercased())",
                    label: model,
                    duration: weekDuration,
                    usedFraction: usedFraction,
                    resetsAt: resetsAt
                )
            default:
                return nil
            }
        }
    }
}
