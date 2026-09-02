import Foundation

/// Usage for OpenCode.
///
/// OpenCode's subscription, OpenCode Go, meters a rolling 5-hour window, a
/// weekly one (Monday to Monday, UTC) and a monthly one anchored to the
/// subscription date. The API key OpenCode stores after `/connect` in
/// `~/.local/share/opencode/auth.json` is the static key the CLI itself
/// sends; it never expires and there is no refresh flow, so a rejected key
/// means the user rotated it and has to reconnect.
///
/// Zen pay-as-you-go credits have no key-authenticated endpoint, only the
/// browser dashboard shows them, so a workspace without a Go subscription
/// answers 403 and reports `notAvailable`. There is nothing to show for it.
struct OpenCodeUsageProvider: HTTPUsageProvider {
    let id = "opencode"
    let name = "OpenCode"
    let logoAssetName = "OpenCodeLogo"
    let usageURL = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    /// OpenCode's data directory, created on first run. `XDG_DATA_HOME` can
    /// move it, but a login-item app never sees the shell's exports, so only
    /// the default location is checked.
    private static let dataDirectory = ".local/share/opencode"

    var isInstalled: Bool {
        CredentialSupport.homePathExists(Self.dataDirectory)
    }

    /// The Go key first; a Zen key from the workspace member who holds the
    /// Go subscription is accepted by the endpoint too.
    func authHeaders() throws -> [String: String] {
        struct Entry: Decodable {
            var key: String?
        }

        guard let auth: [String: Entry] = CredentialSupport.homeJSON("\(Self.dataDirectory)/auth.json"),
              let key = auth["opencode-go"]?.key ?? auth["opencode"]?.key,
              !key.isEmpty
        else {
            throw UsageProviderError.notAvailable
        }
        return ["Authorization": "Bearer \(key)"]
    }

    /// Maps `usage.rolling` / `weekly` / `monthly`, each
    /// `{status, percent, resetsAt}`. `percent` is a whole number 0...100
    /// and `resetsAt` is absolute, computed server-side per request. The
    /// window lengths come from the plan, not the response; the monthly one
    /// is approximated at 30 days since only its reset is known.
    func parseWindows(from data: Data) throws -> [UsageWindow] {
        struct Response: Decodable {
            struct Usage: Decodable {
                var rolling: Window?
                var weekly: Window?
                var monthly: Window?
            }

            struct Window: Decodable {
                var percent: Double
                var resetsAt: String?
            }

            var usage: Usage
        }

        let usage = try JSONDecoder().decode(Response.self, from: data).usage

        func window(_ snapshot: Response.Window?, id: String, duration: TimeInterval) -> UsageWindow? {
            guard let snapshot else { return nil }
            return UsageWindow(
                id: id,
                label: UsageWindow.label(forDuration: duration),
                duration: duration,
                usedFraction: min(max(snapshot.percent / 100, 0), 1),
                resetsAt: snapshot.resetsAt.flatMap(UsageDate.parse)
            )
        }

        return [
            window(usage.rolling, id: "rolling", duration: 5 * 3600),
            window(usage.weekly, id: "weekly", duration: 7 * 24 * 3600),
            window(usage.monthly, id: "monthly", duration: 30 * 24 * 3600),
        ].compactMap(\.self)
    }
}
