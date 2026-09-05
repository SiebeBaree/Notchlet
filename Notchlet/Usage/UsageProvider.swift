import Foundation

/// One agent CLI's live limits. Reads only the CLI's own state and its
/// usage endpoint, and never spends usage to do it. Endpoint-backed
/// providers adopt `HTTPUsageProvider`; adopt this directly only for one
/// that is not HTTP-shaped.
protocol UsageProvider: Sendable {
    var id: String { get }
    var name: String { get }
    /// A template image, so the UI can tint it.
    var logoAssetName: String { get }
    /// Decides the default of the settings toggle; a stored choice wins.
    var isInstalled: Bool { get }
    /// In the order auto tries them.
    var authOptions: [AuthOption] { get }
    /// "Run claude to sign in", no trailing period.
    var signInHint: String { get }
    var history: (any UsageHistorySource)? { get }
    var secrets: (any SecretScanSource)? { get }

    func fetchUsage() async throws -> UsageSnapshot
}

extension UsageProvider {
    var history: (any UsageHistorySource)? { nil }
    var secrets: (any SecretScanSource)? { nil }
}

/// An endpoint-backed provider: the URL, the headers per auth option and
/// the response mapping. `fetchUsage` is shared.
protocol HTTPUsageProvider: UsageProvider {
    var usageURL: URL { get }
    /// Throws `notAvailable` when the option has no usable credential.
    func authHeaders(for option: AuthOption) async throws -> [String: String]
    func parseWindows(from data: Data) throws -> [UsageWindow]
    /// Drops credentials cached between fetches for this option and reports
    /// whether there were any, so a rejection can be retried with a fresh
    /// read once.
    func forgetCredentials(for option: AuthOption) -> Bool
}

extension HTTPUsageProvider {
    func forgetCredentials(for option: AuthOption) -> Bool {
        false
    }

    func fetchUsage() async throws -> UsageSnapshot {
        try await ProviderAuthSettings.selection(for: id, options: authOptions)
            .firstUsable(authOptions, fetch(via:))
    }

    /// A provider holding cached credentials gets a second attempt with a
    /// fresh read, so a token the CLI rotated behind our back costs one
    /// extra round trip rather than a visible error. Anything the endpoint
    /// still rejects after that is a real logout.
    private func fetch(via option: AuthOption) async throws -> UsageSnapshot {
        if let snapshot = try await fetchOnce(via: option) {
            return snapshot
        }
        if forgetCredentials(for: option), let snapshot = try await fetchOnce(via: option) {
            return snapshot
        }
        throw ProviderError.notAvailable(.rejected)
    }

    /// Nil when the endpoint rejected the credentials (401 or 403).
    private func fetchOnce(via option: AuthOption) async throws -> UsageSnapshot? {
        var request = URLRequest(url: usageURL)
        for (header, value) in try await authHeaders(for: option) {
            request.setValue(value, forHTTPHeaderField: header)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.requestFailed
        }
        if http.statusCode == 429 {
            // Retry-After can also be an HTTP-date; the scheduler's own
            // backoff covers that case, so only the seconds form is parsed.
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw ProviderError.rateLimited(retryAfter: retryAfter)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            return nil
        }
        guard http.statusCode == 200 else {
            throw ProviderError.requestFailed
        }
        return try UsageSnapshot(
            windows: parseWindows(from: data),
            fetchedAt: .now,
            authOptionID: option.id
        )
    }
}

enum ProviderError: Error {
    case notAvailable(AuthProblem)
    /// A non-success response, or a transient step such as a token refresh
    /// that could not complete.
    case requestFailed
    /// `retryAfter` is the Retry-After header in seconds, when parseable.
    case rateLimited(retryAfter: TimeInterval?)
}
