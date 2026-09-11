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

    @Test func tokenRotationAndExpiredCacheReuseTheStorageKey() async throws {
        var payload = sealed
        var reads = 0
        let reader = ClaudeDesktopTokenCache.Reader(readCache: { payload }, readPassword: {
            reads += 1
            return password
        })
        #expect(try await reader.read()?.accessToken == "sk-ant-oat01-desktop")
        // A new token encrypted with the same storage key, already expired.
        payload =
            try #require(
                Data(
                    base64Encoded: "djEwWUm2im8/6dfndgk1nItaXcZJvGBkmERLyUQ5FgipfJHqn7Mhahpvdhhl39onBNXDFjkjgWrFWci3iCtSjiQBYu38Sps76100FHJ25/GnQ4RCi/uYdUdxIx6xX5AVBGUaY2VEpMHPH5prqurs3ft2/LwHgMiV5gwFQJ2KLKjKcH8="
                )
            )
        let rotated = try await reader.read()
        #expect(rotated?.accessToken == "rotated")
        #expect(rotated?.expiresAt == Date(timeIntervalSince1970: 1))
        #expect(try await reader.read() == rotated)
        reader.retryAccess()
        #expect(try await reader.read() == rotated)
        #expect(reads == 1)
    }

    @Test func deniedAccessWaitsForExplicitRetryEvenWhenTheFileChanges() async throws {
        var reads = 0
        var payload = sealed
        let reader = ClaudeDesktopTokenCache.Reader(readCache: { payload }, readPassword: {
            reads += 1
            return reads == 1 ? nil : password
        })
        for _ in 0 ..< 2 {
            do {
                _ = try await reader.read()
                Issue.record("Expected paused Keychain access")
            } catch ProviderError.notAvailable(.keychainAccess) {} catch {
                Issue.record("Unexpected error: \(error)")
            }
            payload = Data("changed".utf8)
        }
        #expect(reads == 1)
        payload = sealed
        reader.retryAccess()
        #expect(try await reader.read()?.accessToken == "sk-ant-oat01-desktop")
        #expect(reads == 2)
    }

    @Test func wrongStorageKeyRequiresExplicitRetry() async throws {
        var reads = 0
        let reader = ClaudeDesktopTokenCache.Reader(readCache: { sealed }, readPassword: {
            reads += 1
            return reads == 1 ? "old-key" : password
        })
        for _ in 0 ..< 2 {
            do {
                _ = try await reader.read()
                Issue.record("Expected paused Keychain access")
            } catch ProviderError.notAvailable(.keychainAccess) {} catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
        #expect(reads == 1)
        reader.retryAccess()
        #expect(try await reader.read()?.accessToken == "sk-ant-oat01-desktop")
        #expect(reads == 2)
    }

    @Test func overlappingReadsSharePermissionRequestDespiteCancellation() async throws {
        var reads = 0
        var resume: CheckedContinuation<String?, Never>?
        let reader = ClaudeDesktopTokenCache.Reader(readCache: { sealed }, readPassword: {
            reads += 1
            return await withCheckedContinuation { resume = $0 }
        })
        let first = Task { try await reader.read() }
        while resume == nil {
            await Task.yield()
        }
        first.cancel()
        reader.retryAccess()
        let second = Task { try await reader.read() }
        await Task.yield()
        resume?.resume(returning: password)
        #expect(try await first.value == second.value)
        #expect(reads == 1)
    }

    @Test func missingCacheDoesNotReadKeychain() async throws {
        var reads = 0
        let reader = ClaudeDesktopTokenCache.Reader(readCache: { nil }, readPassword: {
            reads += 1
            return password
        })
        #expect(try await reader.read() == nil)
        #expect(reads == 0)
    }

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
