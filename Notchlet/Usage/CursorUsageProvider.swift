import Foundation

/// Reads the token Cursor.app keeps in its state database and calls the
/// endpoint behind the dashboard's usage page, which takes the token as the
/// `WorkosCursorSessionToken` cookie prefixed with the user id from its
/// `sub` claim. Included usage is a monthly budget in two pools, Cursor's
/// own models and third-party models, on one billing cycle; on-demand
/// spend past it is a bill, not a limit, and is left out. The token is
/// never refreshed: Cursor.app rotates it itself.
struct CursorUsageProvider: HTTPUsageProvider {
    let id = "cursor"
    let name = "Cursor"
    let logoAssetName = "CursorLogo"
    let usageURL = URL(string: "https://cursor.com/api/usage-summary")!
    let signInHint = "Sign in to Cursor, or paste a session token"

    static let appOption = AuthOption(id: "app", label: "Cursor app")
    static let tokenOption = AuthOption(id: "token", label: "Pasted token", secretName: "session token")
    let authOptions = [Self.appOption, Self.tokenOption]
    let history: (any UsageHistorySource)? = CursorHistorySource()

    private static let stateDatabase = "Library/Application Support/Cursor/User/globalStorage/state.vscdb"

    var isInstalled: Bool {
        CredentialSupport.homePathExists("Library/Application Support/Cursor")
            || CredentialSupport.homePathExists(".cursor")
    }

    func authHeaders(for option: AuthOption) async throws -> [String: String] {
        try await Self.sessionHeaders(for: option)
    }

    /// The history source sends the same cookie to the usage export.
    static func sessionHeaders(for option: AuthOption) async throws -> [String: String] {
        let token: String? = if option.id == tokenOption.id {
            await PastedSecrets.read(providerID: "cursor", optionID: option.id)
        } else {
            await CredentialSupport.sqliteValue(
                homePath: stateDatabase,
                table: "ItemTable",
                key: "cursorAuth/accessToken"
            )
        }
        guard let token else {
            throw ProviderError.notAvailable(.signedOut)
        }
        guard let cookie = sessionCookie(token: token) else {
            throw ProviderError.notAvailable(.expired)
        }
        return ["Accept": "application/json", "Cookie": cookie]
    }

    /// Takes the bare JWT Cursor.app stores, or the cookie as copied from a
    /// browser: the value alone or with its name, separator raw or
    /// percent-encoded. Nil when the token is expired or has no subject.
    static func sessionCookie(token: String, now: Date = .now) -> String? {
        var pasted = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = pasted.firstIndex(of: "="), pasted[..<separator] == "WorkosCursorSessionToken" {
            pasted = String(pasted[pasted.index(after: separator)...])
        }
        let jwt = pasted.replacingOccurrences(of: "%3A%3A", with: "::")
            .components(separatedBy: "::").last ?? pasted
        guard let claims = CredentialSupport.jwtClaims(of: jwt),
              let exp = claims["exp"] as? TimeInterval, Date(timeIntervalSince1970: exp) > now,
              let subject = claims["sub"] as? String,
              let userID = subject.split(separator: "|").last, !userID.isEmpty
        else { return nil }
        return "WorkosCursorSessionToken=\(userID)%3A%3A\(jwt)"
    }

    /// The three percent fields of `individualUsage.plan` are the headline
    /// and the two pools. Accounts without percentages (team, enterprise)
    /// fall back to the first spend meter with a cap. Percent fields are
    /// already percentages, even below 1.
    func parseWindows(from data: Data) throws -> [UsageWindow] {
        struct Response: Decodable {
            struct Meter: Decodable {
                var used: Double?
                var limit: Double?
                var totalPercentUsed: Double?
                var autoPercentUsed: Double?
                var apiPercentUsed: Double?
            }

            struct IndividualUsage: Decodable {
                var plan: Meter?
                var overall: Meter?
            }

            struct TeamUsage: Decodable {
                var pooled: Meter?
            }

            var billingCycleStart: String?
            var billingCycleEnd: String?
            var individualUsage: IndividualUsage?
            var teamUsage: TeamUsage?
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        let cycleStart = response.billingCycleStart.flatMap(UsageDate.parse)
        let cycleEnd = response.billingCycleEnd.flatMap(UsageDate.parse)
        let duration: TimeInterval = if let cycleStart, let cycleEnd, cycleEnd > cycleStart {
            cycleEnd.timeIntervalSince(cycleStart)
        } else {
            30 * 24 * 3600
        }

        func window(_ id: String, _ label: String, percent: Double?) -> UsageWindow? {
            guard let percent else { return nil }
            return UsageWindow(
                id: id,
                label: label,
                duration: duration,
                usedFraction: min(max(percent / 100, 0), 1),
                resetsAt: cycleEnd
            )
        }

        let plan = response.individualUsage?.plan
        let pools = [
            window("total", "Monthly", percent: plan?.totalPercentUsed),
            window("cursor-models", "Cursor models", percent: plan?.autoPercentUsed),
            window("other-models", "Other models", percent: plan?.apiPercentUsed),
        ].compactMap(\.self)
        if !pools.isEmpty {
            return pools
        }

        let meters = [plan, response.individualUsage?.overall, response.teamUsage?.pooled]
        let spentPercent = meters.lazy.compactMap { meter -> Double? in
            guard let used = meter?.used, let limit = meter?.limit, limit > 0 else { return nil }
            return used / limit * 100
        }.first
        return [window("total", "Monthly", percent: spentPercent)].compactMap(\.self)
    }
}
