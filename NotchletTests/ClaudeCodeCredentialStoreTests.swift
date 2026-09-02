import Foundation
@testable import Notchlet
import Testing

/// The parts of the store that are pure naming: which keychain item and
/// which lock paths belong to a config directory. Nothing here touches the
/// keychain or the network.
struct ClaudeCodeCredentialStoreTests {
    @Test func defaultConfigDirUsesClaudeCodesPlainServiceName() {
        #expect(ClaudeCodeCredentialStore().keychainService == "Claude Code-credentials")
    }

    @Test func otherConfigDirsGetClaudeCodesHashSuffix() {
        let store = ClaudeCodeCredentialStore(configDir: URL(filePath: "/tmp/claude-work"))
        let service = store.keychainService
        // sha256("/tmp/claude-work") starts with these eight hex digits.
        #expect(service.hasPrefix("Claude Code-credentials-"))
        #expect(service.count == "Claude Code-credentials-".count + 8)
        #expect(service != ClaudeCodeCredentialStore(configDir: URL(filePath: "/tmp/claude-home")).keychainService)
    }

    @Test func accountNameFallsBackLikeClaudeCode() {
        #expect(ClaudeCodeCredentialStore.keychainAccount(userName: "siebe.b-2") == "siebe.b-2")
        #expect(ClaudeCodeCredentialStore.keychainAccount(userName: "sië be") == "claude-code-user")
    }

    @Test func lockPathsMatchClaudeCodes() {
        let store = ClaudeCodeCredentialStore(configDir: URL(filePath: "/tmp/claude-work"))
        #expect(store.refreshLockURL.path == "/tmp/claude-work/.oauth_refresh.lock")
        #expect(store.storageWriteLockURL.path == "/tmp/claude-work/.storage-write.lock")
        #expect(store.legacyRefreshLockURL.path.hasSuffix("/claude-work.lock"))
        #expect(store.fileURL.path == "/tmp/claude-work/.credentials.json")
    }
}
