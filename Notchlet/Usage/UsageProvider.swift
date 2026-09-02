import Foundation

/// A source of usage data for one agent CLI.
///
/// Implementations read the CLI's local state (credentials, config) or call
/// the same usage endpoint the CLI itself calls. They must never consume
/// usage: fetching a snapshot cannot count against any limit.
///
/// Nearly every CLI exposes usage as an authenticated GET returning JSON.
/// Those providers adopt `HTTPUsageProvider` and only supply the endpoint,
/// the auth headers and the response mapping. Adopt this base protocol
/// directly only for a provider that is not HTTP-shaped (say, one that reads
/// session logs).
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

    func fetchUsage() async throws -> UsageSnapshot
}

/// The declarative shape of an endpoint-backed provider. `fetchUsage` comes
/// for free, so a new provider is three small members.
protocol HTTPUsageProvider: UsageProvider {
    var usageURL: URL { get }
    /// Headers authenticating the request, built from the CLI's local state.
    /// Throws `notAvailable` when the CLI has no usable login. Async because
    /// a keychain read goes through a child process.
    func authHeaders() async throws -> [String: String]
    /// Maps the endpoint's response body to usage windows.
    func parseWindows(from data: Data) throws -> [UsageWindow]
    /// Plan tier from the same response, if it exposes one. Feeds anonymous
    /// analytics only; defaults to nil.
    func parsePlanTier(from data: Data) -> String?
    /// Drops any credentials the provider caches between fetches and reports
    /// whether there was anything to drop. Called when the endpoint rejects
    /// them, to decide whether a retry with a fresh read could say anything
    /// new. Defaults to false for providers that read credentials every time.
    func forgetCredentials() -> Bool
}

extension HTTPUsageProvider {
    func parsePlanTier(from data: Data) -> String? {
        nil
    }

    func forgetCredentials() -> Bool {
        false
    }

    /// One request. A provider holding cached credentials gets a second
    /// attempt with a fresh read, so a token the CLI rotated behind our back
    /// costs one extra round trip rather than a visible error. Anything the
    /// endpoint still rejects after that is a real logout, which reads the
    /// same as never having logged in.
    func fetchUsage() async throws -> UsageSnapshot {
        do {
            return try await fetchOnce()
        } catch UsageProviderError.unauthorized {
            guard forgetCredentials() else {
                throw UsageProviderError.notAvailable
            }
            do {
                return try await fetchOnce()
            } catch UsageProviderError.unauthorized {
                throw UsageProviderError.notAvailable
            }
        }
    }

    private func fetchOnce() async throws -> UsageSnapshot {
        var request = URLRequest(url: usageURL)
        for (header, value) in try await authHeaders() {
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
            // elsewhere. `fetchUsage` tells those apart and settles on
            // `notAvailable`; there is nothing here to back off from.
            throw UsageProviderError.unauthorized
        }
        guard http.statusCode == 200 else {
            throw UsageProviderError.requestFailed
        }
        return try UsageSnapshot(
            windows: parseWindows(from: data),
            fetchedAt: .now,
            planTier: parsePlanTier(from: data)
        )
    }
}

enum UsageProviderError: Error {
    /// The CLI is not installed, never logged in, the login expired, or the
    /// endpoint rejected the credentials.
    case notAvailable
    /// The usage endpoint returned a non-success response.
    case requestFailed
    /// The usage endpoint rejected the credentials (401 or 403). Internal to
    /// `fetchUsage`, which retries once with a fresh read and then reports
    /// `notAvailable`; the store never sees this case.
    case unauthorized
    /// The usage endpoint returned 429; `retryAfter` is its Retry-After
    /// header in seconds, when present and parseable.
    case rateLimited(retryAfter: TimeInterval?)
}
