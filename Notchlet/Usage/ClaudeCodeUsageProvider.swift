import Foundation
import os

/// Usage for Claude Code.
///
/// Reads the OAuth access token Claude Code stored at login (macOS keychain,
/// with `~/.claude/.credentials.json` as fallback) and calls the same usage
/// endpoint Claude Code's `/usage` screen calls. Claude Code rotates the
/// token every 8 hours while it runs, rewriting the keychain item each time;
/// see `CredentialSupport.keychainJSON` for why that read stays silent.
/// Tokens are never refreshed here: rotating the refresh token behind Claude
/// Code's back would break its session, so an expired token just reports
/// `notAvailable` until the user runs Claude Code again.
struct ClaudeCodeUsageProvider: HTTPUsageProvider {
    let id = "claude-code"
    let name = "Claude"
    let logoAssetName = "ClaudeLogo"
    let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    var isInstalled: Bool {
        CredentialSupport.homePathExists(".claude")
    }

    private static let sessionDuration: TimeInterval = 5 * 3600
    private static let weekDuration: TimeInterval = 7 * 24 * 3600

    /// The last credentials read, reused until they expire. The keychain
    /// read spawns a process and a token lasts hours, so reading once per
    /// token instead of once per refresh keeps the open panel's 60s cadence
    /// from forking `security` every minute. A rejected request clears this
    /// (see `HTTPUsageProvider.fetchUsage`) in case the server retired the
    /// old token when Claude Code rotated it.
    private let cachedCredentials = OSAllocatedUnfairLock<Credentials?>(initialState: nil)

    func authHeaders() async throws -> [String: String] {
        if let cached = cachedCredentials.withLock({ $0 }), cached.expiresAt > .now {
            return Self.headers(token: cached.accessToken)
        }
        let candidates: [Credentials?] = await [
            CredentialSupport.keychainJSON(service: "Claude Code-credentials"),
            CredentialSupport.homeJSON(".claude/.credentials.json"),
        ]
        let credentials = candidates.compactMap(\.self).first { $0.expiresAt > .now }
        cachedCredentials.withLock { $0 = credentials }
        guard let credentials else {
            throw UsageProviderError.notAvailable
        }
        return Self.headers(token: credentials.accessToken)
    }

    func forgetCredentials() -> Bool {
        cachedCredentials.withLock { credentials in
            let hadCredentials = credentials != nil
            credentials = nil
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

    private struct Credentials: Decodable, Sendable {
        struct OAuth: Decodable, Sendable {
            var accessToken: String
            var expiresAt: Double // milliseconds since epoch
        }

        var claudeAiOauth: OAuth

        var accessToken: String { claudeAiOauth.accessToken }
        var expiresAt: Date { Date(timeIntervalSince1970: claudeAiOauth.expiresAt / 1000) }
    }
}
