import Foundation
@testable import Notchlet
import Testing

struct CodexUsageProviderTests {
    /// Trimmed from a real wham/usage response on the Go plan: one 30-day
    /// window, no secondary.
    private let goPlanFixture = Data("""
    {
      "plan_type": "go",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {
          "used_percent": 12,
          "limit_window_seconds": 2592000,
          "reset_after_seconds": 2592001,
          "reset_at": 1790590498
        },
        "secondary_window": null
      }
    }
    """.utf8)

    @Test func parsesSingleWindowPlan() throws {
        let windows = try CodexUsageProvider().parseWindows(from: goPlanFixture)

        #expect(windows.count == 1)
        #expect(windows[0].id == "primary")
        #expect(windows[0].label == "Monthly")
        #expect(windows[0].duration == 2_592_000)
        #expect(windows[0].usedFraction == 0.12)
        #expect(windows[0].resetsAt == Date(timeIntervalSince1970: 1_790_590_498))
    }

    @Test func parsesDualWindowPlan() throws {
        let data = Data("""
        {
          "rate_limit": {
            "primary_window": { "used_percent": 40, "limit_window_seconds": 18000, "reset_at": 1790000000 },
            "secondary_window": { "used_percent": 65, "limit_window_seconds": 604800, "reset_at": 1790500000 }
          }
        }
        """.utf8)
        let windows = try CodexUsageProvider().parseWindows(from: data)

        #expect(windows.map(\.label) == ["5h", "Weekly"])
        #expect(windows.map(\.usedFraction) == [0.4, 0.65])
    }

    @Test func parsesPlanTier() {
        #expect(CodexUsageProvider().parsePlanTier(from: goPlanFixture) == "go")
        #expect(CodexUsageProvider().parsePlanTier(from: Data("{}".utf8)) == nil)
    }

    @Test func missingRateLimitGivesNoWindows() throws {
        #expect(try CodexUsageProvider().parseWindows(from: Data("{}".utf8)).isEmpty)
    }
}

struct CredentialSupportTests {
    @Test func readsJWTExpiry() {
        // Unsigned JWT with payload {"exp": 1790000000}.
        let payload = Data("{\"exp\": 1790000000}".utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let token = "eyJhbGciOiJub25lIn0.\(payload).sig"
        #expect(CredentialSupport.jwtExpiry(of: token) == Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test func rejectsMalformedTokens() {
        #expect(CredentialSupport.jwtExpiry(of: "not-a-jwt") == nil)
        #expect(CredentialSupport.jwtExpiry(of: "a.b.c") == nil)
    }

    /// `hex()` output for a UTF-8 text value and for the same token stored
    /// as a UTF-16 blob; dropping NULs makes both read the same.
    @Test func decodesSQLiteHexValues() {
        #expect(CredentialSupport.data(fromHex: "65794A2E") == Data("eyJ.".utf8))
        #expect(CredentialSupport.data(fromHex: "650079004A002E00").filter { $0 != 0 } == Data("eyJ.".utf8))
        #expect(CredentialSupport.data(fromHex: "zz").isEmpty)
        #expect(CredentialSupport.data(fromHex: "").isEmpty)
    }

    @Test func keychainNamesThatWouldBreakTheQuotingAreRefused() {
        #expect(CredentialSupport.isPlainKeychainName("Claude Code-credentials"))
        #expect(CredentialSupport.isPlainKeychainName("cursor.token"))
        #expect(!CredentialSupport.isPlainKeychainName(""))
        #expect(!CredentialSupport.isPlainKeychainName("a\"b"))
        #expect(!CredentialSupport.isPlainKeychainName("a\\b"))
        #expect(!CredentialSupport.isPlainKeychainName("a\nb"))
    }
}
