import Foundation

/// A source of usage data for one agent CLI.
///
/// Implementations read the CLI's local state (credentials, config) or call
/// the same usage endpoint the CLI itself calls. They must never consume
/// usage: fetching a snapshot cannot count against any limit.
///
/// Nearly every CLI exposes usage as an authenticated GET returning JSON.
/// Those providers adopt `HTTPUsageProvider` and only supply the endpoint,
/// the auth headers per option and the response mapping. Adopt this base
/// protocol directly only for a provider that is not HTTP-shaped (say, one
/// that reads session logs).
/// Sendable so the store can fetch several providers concurrently;
/// implementations are stateless structs.
protocol UsageProvider: Sendable {
    /// Stable identifier, used as a dictionary key and for settings.
    var id: String { get }
    /// Display name shown in the UI.
    var name: String { get }
    /// Asset catalog name of the provider's logo, a template image so the UI
    /// can tint it.
    var logoAssetName: String { get }
    /// Whether the CLI appears to be installed on this machine. Only decides
    /// the default of the provider's settings toggle; a stored user choice
    /// always wins.
    var isInstalled: Bool { get }
    /// Ways to obtain credentials, in the order auto tries them. The
    /// settings page offers them as a picker when there is more than one.
    var authOptions: [AuthOption] { get }
    /// What to do when there is no usable login, without trailing period,
    /// e.g. "Run claude to sign in". Shown after the reason on the settings
    /// page.
    var signInHint: String { get }
    /// Where the provider's past usage can be read from, for the history
    /// pane. Nil for a provider that only has live limits to show.
    var history: (any UsageHistorySource)? { get }
    /// Where the provider's chats can be scanned for leaked keys. Nil for
    /// a provider without chat logs on disk.
    var secrets: (any SecretScanSource)? { get }

    func fetchUsage() async throws -> UsageSnapshot
}

extension UsageProvider {
    var history: (any UsageHistorySource)? { nil }
    var secrets: (any SecretScanSource)? { nil }
}

/// The declarative shape of an endpoint-backed provider. `fetchUsage` comes
/// for free, so a new provider is a few small members.
protocol HTTPUsageProvider: UsageProvider {
    var usageURL: URL { get }
    /// Headers authenticating the request for one auth option, built from
    /// the CLI's local state or a pasted secret. Throws `notAvailable` with
    /// the reason when the option has no usable credential. Async because a
    /// keychain read goes through a child process.
    func authHeaders(for option: AuthOption) async throws -> [String: String]
    /// Maps the endpoint's response body to usage windows.
    func parseWindows(from data: Data) throws -> [UsageWindow]
    /// Plan tier from the same response, if it exposes one. Feeds anonymous
    /// analytics only; defaults to nil.
    func parsePlanTier(from data: Data) -> String?
    /// Drops any credentials the provider caches between fetches for this
    /// option and reports whether there was anything to drop. Called when
    /// the endpoint rejects them, to decide whether a retry with a fresh
    /// read could say anything new. Defaults to false for providers that
    /// read credentials every time.
    func forgetCredentials(for option: AuthOption) -> Bool
}

extension HTTPUsageProvider {
    func parsePlanTier(from data: Data) -> String? {
        nil
    }

    func forgetCredentials(for option: AuthOption) -> Bool {
        false
    }

    /// Tries the auth options the user's selection allows, in order, and
    /// answers from the first one that works. An option without a usable
    /// credential moves on to the next; the most specific problem found is
    /// what gets reported when none works, so an expired login is never
    /// reported as merely signed out because an empty fallback came last.
    /// Anything else, a rate limit or a network failure, stops the walk:
    /// it says nothing about the other options and the scheduler's backoff
    /// handles it.
    func fetchUsage() async throws -> UsageSnapshot {
        let options = ProviderAuthSettings.selection(for: id, options: authOptions).resolve(authOptions)
        var problem = AuthProblem.signedOut
        for option in options {
            do {
                return try await fetch(via: option)
            } catch let UsageProviderError.notAvailable(found) {
                problem = max(problem, found)
            }
        }
        throw UsageProviderError.notAvailable(problem)
    }

    /// One option. A provider holding cached credentials gets a second
    /// attempt with a fresh read, so a token the CLI rotated behind our back
    /// costs one extra round trip rather than a visible error. Anything the
    /// endpoint still rejects after that is a real logout.
    private func fetch(via option: AuthOption) async throws -> UsageSnapshot {
        do {
            return try await fetchOnce(via: option)
        } catch UsageProviderError.unauthorized {
            guard forgetCredentials(for: option) else {
                throw UsageProviderError.notAvailable(.rejected)
            }
            do {
                return try await fetchOnce(via: option)
            } catch UsageProviderError.unauthorized {
                throw UsageProviderError.notAvailable(.rejected)
            }
        }
    }

    private func fetchOnce(via option: AuthOption) async throws -> UsageSnapshot {
        var request = URLRequest(url: usageURL)
        for (header, value) in try await authHeaders(for: option) {
            request.setValue(value, forHTTPHeaderField: header)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageProviderError.requestFailed
        }
        if http.statusCode == 429 {
            // Retry-After can also be an HTTP-date; the scheduler's own
            // backoff covers that case, so only the seconds form is parsed.
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw UsageProviderError.rateLimited(retryAfter: retryAfter)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            // A token that passed the local expiry check but the server
            // rejects: rotated behind our back, revoked, or logged out
            // elsewhere. `fetch(via:)` tells those apart and settles on
            // `notAvailable`; there is nothing here to back off from.
            throw UsageProviderError.unauthorized
        }
        guard http.statusCode == 200 else {
            throw UsageProviderError.requestFailed
        }
        return try UsageSnapshot(
            windows: parseWindows(from: data),
            fetchedAt: .now,
            planTier: parsePlanTier(from: data),
            authOptionID: option.id
        )
    }
}

enum UsageProviderError: Error {
    /// No usable credential: the CLI is not installed or signed in, the
    /// login expired, or the endpoint rejected it. The problem says which.
    case notAvailable(AuthProblem)
    /// The usage endpoint returned a non-success response, or a transient
    /// step such as a token refresh could not complete.
    case requestFailed
    /// The usage endpoint rejected the credentials (401 or 403). Internal to
    /// `fetchUsage`, which retries once with a fresh read and then reports
    /// `notAvailable`; the store never sees this case.
    case unauthorized
    /// The usage endpoint returned 429; `retryAfter` is its Retry-After
    /// header in seconds, when present and parseable.
    case rateLimited(retryAfter: TimeInterval?)
}
