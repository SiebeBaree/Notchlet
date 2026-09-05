import Foundation
@testable import Notchlet
import Testing

struct ClaudeDesktopTokenCacheTests {
    /// A cache with one Code tab entry, sealed the way Electron's
    /// safeStorage does it under the password below.
    private let sealed = Data(base64Encoded: """
    djEwKDoCC01lU8oWv5BRy0Tj89E5pWHY9xlMyB8eAqe+eapLQJCijIkI988vCoB0TrMP6E4uhqyr+ux7EO+4aOa2poR43yu8ftl3z3S/\
    Pr6ESwjUiX1RUrspIStklFR7WY96XgBVCv2b32ErJC608OBDcr4nSWWNjeiCsdGZPbd6CkIvkExoVPRPCGqsVw2igjkJhLdWu8z7j8pD\
    TOZlB2Ybw31KJuMWbxsi9oCjNR27hdwnFO5pBpVY7TX/ypekx/eod6lmBtYxbv0cIm80BwIqXJ7AQHeL6HjZfJtu+Pz+/tkYjdq6y3Cj\
    yroEJr3lTdxRti2u7Y4FmVhI76A12DlVBHXfg1MmaqY9jVIbcRIhTZQ=
    """)!
    private let password = "notchlet-test-password"

    @Test func decryptsElectronSafeStorage() throws {
        let json = try #require(ClaudeDesktopTokenCache.decrypt(sealed, password: password))
        let token = try #require(ClaudeDesktopTokenCache.token(in: json))

        #expect(token.accessToken == "sk-ant-oat01-desktop")
        #expect(token.expiresAt == Date(timeIntervalSince1970: 1_893_456_000))
    }

    /// A wrong key can still come out with valid padding, so the check is
    /// that nothing readable comes out.
    @Test func wrongPasswordOrPrefixYieldsNothing() {
        let garbage = ClaudeDesktopTokenCache.decrypt(sealed, password: "other")
        #expect(garbage.flatMap { ClaudeDesktopTokenCache.token(in: $0) } == nil)
        #expect(ClaudeDesktopTokenCache.decrypt(Data("v11abc".utf8), password: password) == nil)
    }

    @Test func prefersTheCodeTabScopeThenTheLatestExpiry() throws {
        let clientID = ClaudeTokenRefresh.clientID
        let json = Data("""
        {
          "acct:a|\(
              clientID
          ):org_1:https://api.anthropic.com:user:inference user:profile": { "token": "old", "expiresAt": 1000000 },
          "acct:a|\(
              clientID
          ):org_2:https://api.anthropic.com:user:inference user:profile": { "token": "long", "expiresAt": 9000000 },
          "acct:a|\(clientID):org_3:https://api.anthropic.com:user:inference": null,
          "acct:a|other-client:org_1:https://api.anthropic.com:user:profile user:sessions:claude_code": { "token": "chat", "expiresAt": 9000000 },
          "\(clientID):org_0:https://api.anthropic.com:user:inference": { "token": "", "expiresAt": 9000000 }
        }
        """.utf8)
        #expect(try #require(ClaudeDesktopTokenCache.token(in: json)).accessToken == "long")

        let withCodeTab = Data("""
        {
          "acct:a|\(
              clientID
          ):org_2:https://api.anthropic.com:user:inference user:profile": { "token": "long", "expiresAt": 9000000 },
          "acct:a|\(
              clientID
          ):org_2:https://api.anthropic.com:user:inference user:profile user:sessions:claude_code": { "token": "tab", "expiresAt": 2000000 }
        }
        """.utf8)
        let token = try #require(ClaudeDesktopTokenCache.token(in: withCodeTab))
        #expect(token.accessToken == "tab")
        #expect(token.expiresAt == Date(timeIntervalSince1970: 2000))
    }

    @Test func emptyCacheYieldsNothing() {
        #expect(ClaudeDesktopTokenCache.token(in: Data("{}".utf8)) == nil)
        #expect(ClaudeDesktopTokenCache.token(in: Data("[]".utf8)) == nil)
    }
}
