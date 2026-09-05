import Foundation

/// Reads the tokens in `~/.codex/auth.json` and calls the endpoint behind
/// the CLI's `/status` screen. Which windows exist is decided server-side
/// per plan (5h+weekly on Plus, weekly only on Pro, monthly on Go), so
/// durations and labels come from the response. Tokens are never refreshed:
/// OpenAI rejects a reused refresh token, so a refresh behind the CLI's
/// back could sign it out.
struct CodexUsageProvider: HTTPUsageProvider {
    let id = "codex"
    let name = "Codex"
    let logoAssetName = "OpenAILogo"
    let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    let signInHint = "Run codex login"

    static let cliOption = AuthOption(id: "cli", label: "Codex CLI")
    let authOptions = [Self.cliOption]
    let history: (any UsageHistorySource)? = CodexHistorySource()
    let secrets: (any SecretScanSource)? = CodexSecretSource()

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

        // An API-key login has no tokens object; the endpoint only answers
        // ChatGPT logins.
        guard let auth: Auth = CredentialSupport.homeJSON(".codex/auth.json") else {
            throw ProviderError.notAvailable(.signedOut)
        }
        guard let expiry = CredentialSupport.jwtExpiry(of: auth.tokens.accessToken), expiry > .now else {
            throw ProviderError.notAvailable(.expired)
        }
        var headers = ["Authorization": "Bearer \(auth.tokens.accessToken)"]
        if let accountId = auth.tokens.accountId {
            headers["ChatGPT-Account-Id"] = accountId
        }
        return headers
    }

    func parsePlanTier(from data: Data) -> String? {
        struct Response: Decodable {
            var planType: String?
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode(Response.self, from: data))?.planType
    }

    /// `rate_limit.primary_window` and `secondary_window`, either of which
    /// can be null.
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
