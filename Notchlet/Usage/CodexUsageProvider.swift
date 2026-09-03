import Foundation

/// Usage for OpenAI Codex.
///
/// Reads the OAuth tokens the Codex CLI stores in `~/.codex/auth.json` and
/// calls the exact endpoint behind its `/status` screen. Which windows exist
/// is decided server-side per plan (observed: 5h+weekly on Plus, weekly only
/// on Pro tiers, monthly on an unused Go account), so durations and labels
/// come from the response, never from a plan table — the CLI itself has
/// none. Tokens are never refreshed here: they last ten days and the CLI
/// renews them on use, and OpenAI rejects a reused refresh token, so a
/// refresh behind the CLI's back could sign it out.
struct CodexUsageProvider: HTTPUsageProvider {
    let id = "codex"
    let name = "Codex"
    let logoAssetName = "OpenAILogo"
    let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    let signInHint = "Run codex login"

    static let cliOption = AuthOption(id: "cli", label: "Codex CLI")
    let authOptions = [Self.cliOption]
    let history: (any UsageHistorySource)? = CodexHistorySource()

    var isInstalled: Bool {
        CredentialSupport.homePathExists(".codex")
    }

    func authHeaders(for option: AuthOption) throws -> [String: String] {
        struct Auth: Decodable {
            struct Tokens: Decodable {
                var accessToken: String
                var accountId: String?

                enum CodingKeys: String, CodingKey {
                    case accessToken = "access_token"
                    case accountId = "account_id"
                }
            }

            var tokens: Tokens
        }

        // An API-key login has no tokens object, which reads as signed out:
        // the usage endpoint only answers ChatGPT logins.
        guard let auth: Auth = CredentialSupport.homeJSON(".codex/auth.json") else {
            throw UsageProviderError.notAvailable(.signedOut)
        }
        guard let expiry = CredentialSupport.jwtExpiry(of: auth.tokens.accessToken), expiry > .now else {
            throw UsageProviderError.notAvailable(.expired)
        }
        var headers = ["Authorization": "Bearer \(auth.tokens.accessToken)"]
        if let accountId = auth.tokens.accountId {
            headers["ChatGPT-Account-Id"] = accountId
        }
        return headers
    }

    /// The response carries the ChatGPT plan ("plus", "pro", "go", ...) at
    /// the top level.
    func parsePlanTier(from data: Data) -> String? {
        struct Response: Decodable {
            var planType: String?
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode(Response.self, from: data))?.planType
    }

    /// Maps `rate_limit.primary_window` / `secondary_window`, each
    /// `{used_percent, limit_window_seconds, reset_at}`. Either can be null.
    func parseWindows(from data: Data) throws -> [UsageWindow] {
        struct Response: Decodable {
            struct RateLimit: Decodable {
                var primaryWindow: Window?
                var secondaryWindow: Window?
            }

            struct Window: Decodable {
                var usedPercent: Double
                var limitWindowSeconds: TimeInterval?
                var resetAt: TimeInterval? // unix epoch seconds
            }

            var rateLimit: RateLimit?
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let rateLimit = try decoder.decode(Response.self, from: data).rateLimit

        func window(_ snapshot: Response.Window?, id: String, fallbackDuration: TimeInterval) -> UsageWindow? {
            guard let snapshot else { return nil }
            let duration = snapshot.limitWindowSeconds ?? fallbackDuration
            return UsageWindow(
                id: id,
                label: UsageWindow.label(forDuration: duration),
                duration: duration,
                usedFraction: min(max(snapshot.usedPercent / 100, 0), 1),
                resetsAt: snapshot.resetAt.map(Date.init(timeIntervalSince1970:))
            )
        }

        return [
            window(rateLimit?.primaryWindow, id: "primary", fallbackDuration: 5 * 3600),
            window(rateLimit?.secondaryWindow, id: "secondary", fallbackDuration: 7 * 24 * 3600),
        ].compactMap(\.self)
    }
}
