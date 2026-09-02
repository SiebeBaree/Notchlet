import Foundation
@testable import Notchlet
import Testing

struct CursorUsageProviderTests {
    /// Trimmed from a Pro account's /api/usage-summary response. Money is in
    /// cents, the percent fields are already percentages.
    private let proFixture = Data("""
    {
      "billingCycleStart": "2026-08-15T00:00:00.000Z",
      "billingCycleEnd": "2026-09-15T00:00:00.000Z",
      "membershipType": "pro",
      "limitType": "user",
      "isUnlimited": false,
      "individualUsage": {
        "plan": {
          "enabled": true, "used": 1500, "limit": 2000, "remaining": 500,
          "breakdown": { "included": 2000, "bonus": 0, "total": 1500 },
          "autoPercentUsed": 12.5, "apiPercentUsed": 97.0, "totalPercentUsed": 75.0
        },
        "onDemand": { "enabled": true, "used": 500, "limit": 10000, "remaining": 9500 }
      }
    }
    """.utf8)

    @Test func parsesHeadlineAndBothPools() throws {
        let windows = try CursorUsageProvider().parseWindows(from: proFixture)
        let cycleEnd = try #require(ISO8601DateFormatter().date(from: "2026-09-15T00:00:00Z"))

        #expect(windows.map(\.id) == ["total", "cursor-models", "other-models"])
        #expect(windows.map(\.label) == ["Monthly", "Cursor models", "Other models"])
        #expect(windows.map(\.usedFraction) == [0.75, 0.125, 0.97])
        #expect(windows.allSatisfy { $0.duration == 31 * 24 * 3600 })
        #expect(windows.allSatisfy { $0.resetsAt == cycleEnd })
    }

    /// A JWT with `sub` "auth0|user_123" expiring far in the future; the
    /// signature is junk because nothing here verifies it.
    private let farFutureJWT: String = {
        let header = Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8).base64EncodedString()
        let payload = Data(#"{"sub":"auth0|user_123","exp":4102444800}"#.utf8).base64EncodedString()
        return "\(header).\(payload).sig".replacingOccurrences(of: "=", with: "")
    }()

    @Test func appTokenBecomesTheDashboardCookie() {
        #expect(CursorUsageProvider.sessionCookie(token: farFutureJWT)
            == "WorkosCursorSessionToken=user_123%3A%3A\(farFutureJWT)")
    }

    @Test func pastedCookieValuesAreAcceptedInEveryFormTheBrowserShows() {
        let expected = "WorkosCursorSessionToken=user_123%3A%3A\(farFutureJWT)"
        #expect(CursorUsageProvider.sessionCookie(token: "user_123%3A%3A\(farFutureJWT)") == expected)
        #expect(CursorUsageProvider.sessionCookie(token: "user_123::\(farFutureJWT)") == expected)
        #expect(CursorUsageProvider.sessionCookie(token: "WorkosCursorSessionToken=user_123%3A%3A\(farFutureJWT)\n")
            == expected)
    }

    @Test func expiredOrMalformedTokensGiveNoCookie() {
        #expect(CursorUsageProvider.sessionCookie(token: farFutureJWT, now: .distantFuture) == nil)
        #expect(CursorUsageProvider.sessionCookie(token: "not-a-jwt") == nil)
    }

    @Test func headlineIsTheSummaryGauge() throws {
        let windows = try CursorUsageProvider().parseWindows(from: proFixture)
        #expect(UsageSnapshot(windows: windows, fetchedAt: .now).primaryWindow?.id == "total")
    }

    @Test func percentsBelowOneStayPercents() throws {
        let data = Data("""
        { "individualUsage": { "plan": { "totalPercentUsed": 0.36 } } }
        """.utf8)
        let windows = try CursorUsageProvider().parseWindows(from: data)
        #expect(windows.count == 1)
        #expect(windows[0].usedFraction == 0.0036)
        #expect(windows[0].duration == 30 * 24 * 3600)
        #expect(windows[0].resetsAt == nil)
    }

    @Test func fallsBackToSpendWithoutPercentages() throws {
        let data = Data("""
        { "individualUsage": { "plan": { "used": 1500, "limit": 2000 } } }
        """.utf8)
        let windows = try CursorUsageProvider().parseWindows(from: data)
        #expect(windows.map(\.id) == ["total"])
        #expect(windows[0].usedFraction == 0.75)
    }

    @Test func teamAccountsUseThePooledBudget() throws {
        let data = Data("""
        {
          "limitType": "team",
          "individualUsage": { "onDemand": { "enabled": false, "used": 0, "limit": 0 } },
          "teamUsage": { "pooled": { "enabled": true, "used": 125000, "limit": 500000 } }
        }
        """.utf8)
        let windows = try CursorUsageProvider().parseWindows(from: data)
        #expect(windows.map(\.usedFraction) == [0.25])
    }

    @Test func unlimitedAccountsGiveNoWindows() throws {
        let data = Data("""
        { "isUnlimited": true, "individualUsage": { "plan": { "used": 40, "limit": null } } }
        """.utf8)
        #expect(try CursorUsageProvider().parseWindows(from: data).isEmpty)
    }

    @Test func parsesPlanTier() {
        #expect(CursorUsageProvider().parsePlanTier(from: proFixture) == "pro")
        #expect(CursorUsageProvider().parsePlanTier(from: Data("{}".utf8)) == nil)
    }

    @Test func buildsTheDashboardCookieFromTheToken() throws {
        let token = Self.unsignedJWT(#"{"sub": "auth0|user_01ABC", "exp": 1790000000}"#)
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let cookie = try #require(CursorUsageProvider.sessionCookie(token: token, now: now))
        #expect(cookie == "WorkosCursorSessionToken=user_01ABC%3A%3A\(token)")
    }

    @Test func rejectsExpiredAndSubjectlessTokens() {
        let expired = Self.unsignedJWT(#"{"sub": "auth0|user_01ABC", "exp": 1700000000}"#)
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        #expect(CursorUsageProvider.sessionCookie(token: expired, now: now) == nil)

        let subjectless = Self.unsignedJWT(#"{"exp": 1790000000}"#)
        #expect(CursorUsageProvider.sessionCookie(token: subjectless, now: now) == nil)
    }

    private static func unsignedJWT(_ payload: String) -> String {
        let body = Data(payload.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJub25lIn0.\(body).sig"
    }
}
