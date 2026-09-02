import Foundation
@testable import Notchlet
import Testing

struct ClaudeTokenRefreshTests {
    private let now = Date(timeIntervalSince1970: 1_788_360_000)

    /// The shape Claude Code 2.1 writes, with an MCP entry beside the OAuth
    /// one to prove the merge leaves neighbours alone.
    private let stored = Data("""
    {
      "claudeAiOauth": {
        "accessToken": "sk-ant-oat01-old",
        "refreshToken": "sk-ant-ort01-old",
        "expiresAt": 1788359000000,
        "refreshTokenExpiresAt": 1789841179775,
        "scopes": ["user:profile", "user:inference"],
        "subscriptionType": "max",
        "rateLimitTier": "default_claude_max_20x"
      },
      "mcpOAuth": { "some-server": { "accessToken": "mcp-token" } }
    }
    """.utf8)

    @Test func readsTheOAuthObject() throws {
        let credentials = try #require(ClaudeTokenRefresh.Credentials(json: stored))
        #expect(credentials.accessToken == "sk-ant-oat01-old")
        #expect(credentials.refreshToken == "sk-ant-ort01-old")
        #expect(credentials.scopes == ["user:profile", "user:inference"])
        #expect(credentials.expiresAt == Date(timeIntervalSince1970: 1_788_359_000))
    }

    @Test func expiryIsTheDeadlineItselfNotClaudeCodesEarlyMargin() throws {
        let credentials = try #require(ClaudeTokenRefresh.Credentials(json: stored))
        #expect(credentials.isExpired(now: now))
        #expect(!credentials.isExpired(now: credentials.expiresAt.addingTimeInterval(-60)))
    }

    @Test func clearedRecordReadsAsNoCredentials() {
        let cleared = Data(#"{"claudeAiOauth":{"accessToken":"","refreshToken":"","expiresAt":0}}"#.utf8)
        #expect(ClaudeTokenRefresh.Credentials(json: cleared) == nil)
        #expect(ClaudeTokenRefresh.storedRefreshToken(in: cleared) == nil)
    }

    @Test func requestSendsTheStoredScopesVerbatim() throws {
        let credentials = try #require(ClaudeTokenRefresh.Credentials(json: stored))
        let request = try #require(ClaudeTokenRefresh.request(for: credentials))
        let body = try #require(request.httpBody)
        let fields = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])

        #expect(request.url == ClaudeTokenRefresh.tokenURL)
        #expect(request.httpMethod == "POST")
        #expect(fields == [
            "grant_type": "refresh_token",
            "refresh_token": "sk-ant-ort01-old",
            "client_id": ClaudeTokenRefresh.clientID,
            "scope": "user:profile user:inference",
        ])
    }

    @Test func noRequestWithoutRefreshTokenOrScopes() throws {
        var credentials = try #require(ClaudeTokenRefresh.Credentials(json: stored))
        credentials.scopes = []
        #expect(ClaudeTokenRefresh.request(for: credentials) == nil)
        credentials = try #require(ClaudeTokenRefresh.Credentials(json: stored))
        credentials.refreshToken = nil
        #expect(ClaudeTokenRefresh.request(for: credentials) == nil)
    }

    @Test func mergeReplacesOnlyTheTokenFields() throws {
        let response = try ClaudeTokenRefresh.parse(status: 200, body: Data("""
        { "access_token": "sk-ant-oat01-new", "refresh_token": "sk-ant-ort01-new",
          "expires_in": 28800, "refresh_token_expires_in": 2592000, "scope": "user:profile user:inference" }
        """.utf8))
        let merged = try ClaudeTokenRefresh.merge(response, into: stored, now: now)
        let object = try #require(JSONSerialization.jsonObject(with: merged) as? [String: Any])
        let oauth = try #require(object["claudeAiOauth"] as? [String: Any])

        #expect(oauth["accessToken"] as? String == "sk-ant-oat01-new")
        #expect(oauth["refreshToken"] as? String == "sk-ant-ort01-new")
        #expect((oauth["expiresAt"] as? NSNumber)?.int64Value == 1_788_388_800_000)
        #expect((oauth["refreshTokenExpiresAt"] as? NSNumber)?.int64Value == 1_790_952_000_000)
        #expect(oauth["subscriptionType"] as? String == "max")
        #expect(oauth["rateLimitTier"] as? String == "default_claude_max_20x")
        #expect((object["mcpOAuth"] as? [String: Any])?.keys.contains("some-server") == true)
    }

    @Test func mergeKeepsOldRefreshTokenAndScopesWhenTheReplyOmitsThem() throws {
        let response = try ClaudeTokenRefresh.parse(
            status: 200,
            body: Data(#"{ "access_token": "sk-ant-oat01-new", "expires_in": 28800 }"#.utf8)
        )
        let merged = try ClaudeTokenRefresh.merge(response, into: stored, now: now)
        let credentials = try #require(ClaudeTokenRefresh.Credentials(json: merged))

        #expect(credentials.refreshToken == "sk-ant-ort01-old")
        #expect(credentials.scopes == ["user:profile", "user:inference"])
        #expect(ClaudeTokenRefresh.storedRefreshToken(in: merged) == "sk-ant-ort01-old")
    }

    @Test func invalidGrantIsTheDeadTokenCase() {
        let body = Data(#"{"error":"invalid_grant","error_description":"Refresh token revoked"}"#.utf8)
        #expect(throws: ClaudeTokenRefresh.Failure.invalidGrant) {
            try ClaudeTokenRefresh.parse(status: 400, body: body)
        }
        #expect(throws: ClaudeTokenRefresh.Failure.status(503)) {
            try ClaudeTokenRefresh.parse(status: 503, body: Data())
        }
    }
}
