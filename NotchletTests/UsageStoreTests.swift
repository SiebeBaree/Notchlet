import Foundation
@testable import Notchlet
import Testing

/// Default visibility under the active-provider cap. Uses throwaway
/// provider ids so the real settings keys are never touched. Serialized
/// because every test reads and writes the same UserDefaults keys.
@Suite(.serialized)
struct UsageStoreTests {
    private struct StubProvider: UsageProvider {
        let id: String
        let isInstalled: Bool
        var name: String { id }
        var logoAssetName: String { "ClaudeLogo" }

        func fetchUsage() async throws -> UsageSnapshot {
            throw UsageProviderError.notAvailable
        }
    }

    private let ids = ["test-a", "test-b", "test-c", "test-d"]

    private func clearDefaults() {
        for id in ids {
            UserDefaults.standard.removeObject(forKey: UsageStore.enabledDefaultsKey(id))
        }
    }

    @Test func installedProvidersFillTheSlotsInOrder() {
        clearDefaults()
        defer { clearDefaults() }
        let store = UsageStore(providers: ids.map { StubProvider(id: $0, isInstalled: true) })

        #expect(ids.map(store.isEnabled) == [true, true, true, false])
        #expect(!store.canEnableMore)
    }

    @Test func storedChoicesWinOverInstalledDefaults() {
        clearDefaults()
        defer { clearDefaults() }
        UserDefaults.standard.set(false, forKey: UsageStore.enabledDefaultsKey("test-a"))
        UserDefaults.standard.set(true, forKey: UsageStore.enabledDefaultsKey("test-d"))
        let store = UsageStore(providers: ids.map { StubProvider(id: $0, isInstalled: true) })

        // a is off by choice, d on by choice, so b and c take the two open slots.
        #expect(ids.map(store.isEnabled) == [false, true, true, true])
    }

    @Test func uninstalledProvidersStayOff() {
        clearDefaults()
        defer { clearDefaults() }
        let store = UsageStore(providers: ids.map { StubProvider(id: $0, isInstalled: $0 == "test-b") })

        #expect(ids.map(store.isEnabled) == [false, true, false, false])
        #expect(store.canEnableMore)
    }

    @Test func enablingPastTheCapIsIgnored() {
        clearDefaults()
        defer { clearDefaults() }
        let store = UsageStore(providers: ids.map { StubProvider(id: $0, isInstalled: true) })

        store.setEnabled("test-d", true)
        #expect(!store.isEnabled("test-d"))

        store.setEnabled("test-a", false)
        store.setEnabled("test-d", true)
        #expect(ids.map(store.isEnabled) == [false, true, true, true])
    }
}
