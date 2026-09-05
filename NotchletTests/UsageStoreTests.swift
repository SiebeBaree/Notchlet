import Foundation
@testable import Notchlet
import Testing

/// Default visibility under the active-provider cap, against a throwaway
/// defaults suite so the real settings are never touched.
struct UsageStoreTests {
    private struct StubProvider: UsageProvider {
        let id: String
        let isInstalled: Bool
        var name: String { id }
        var logoAssetName: String { "ClaudeLogo" }
        var authOptions: [AuthOption] { [] }
        var signInHint: String { "" }

        func fetchUsage() async throws -> UsageSnapshot {
            throw ProviderError.notAvailable(.signedOut)
        }
    }

    private let ids = ["test-a", "test-b", "test-c", "test-d"]
    private let defaults: UserDefaults

    init() {
        let suite = "notchlet-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func installedProvidersFillTheSlotsInOrder() {
        let store = UsageStore(providers: ids.map { StubProvider(id: $0, isInstalled: true) }, defaults: defaults)

        #expect(ids.map(store.isEnabled) == [true, true, true, false])
        #expect(!store.canEnableMore)
    }

    @Test func storedChoicesWinOverInstalledDefaults() {
        defaults.set(false, forKey: UsageStore.enabledDefaultsKey("test-a"))
        defaults.set(true, forKey: UsageStore.enabledDefaultsKey("test-d"))
        let store = UsageStore(providers: ids.map { StubProvider(id: $0, isInstalled: true) }, defaults: defaults)

        // a is off by choice, d on by choice, so b and c take the two open slots.
        #expect(ids.map(store.isEnabled) == [false, true, true, true])
    }

    @Test func uninstalledProvidersStayOff() {
        let store = UsageStore(
            providers: ids.map { StubProvider(id: $0, isInstalled: $0 == "test-b") },
            defaults: defaults
        )

        #expect(ids.map(store.isEnabled) == [false, true, false, false])
        #expect(store.canEnableMore)
    }

    @Test func enablingPastTheCapIsIgnored() {
        let store = UsageStore(providers: ids.map { StubProvider(id: $0, isInstalled: true) }, defaults: defaults)

        store.setEnabled("test-d", true)
        #expect(!store.isEnabled("test-d"))

        store.setEnabled("test-a", false)
        store.setEnabled("test-d", true)
        #expect(ids.map(store.isEnabled) == [false, true, true, true])
    }
}
