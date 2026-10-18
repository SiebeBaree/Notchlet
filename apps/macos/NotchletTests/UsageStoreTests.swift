import Foundation
@testable import Notchlet
import Testing

/// Default visibility under the active-provider cap, against a throwaway
/// defaults suite so the real settings are never touched.
struct UsageStoreTests {
    private actor Gate {
        var calls = 0
        var cancellations = 0
        private var release: CheckedContinuation<Void, any Error>?
        private var started: CheckedContinuation<Void, Never>?

        func fetch() async throws {
            calls += 1
            started?.resume()
            started = nil
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { release = $0 }
            } onCancel: {
                Task { await self.cancel() }
            }
        }

        func waitUntilStarted(after previousCalls: Int = 0) async {
            if calls > previousCalls {
                return
            }
            await withCheckedContinuation { started = $0 }
        }

        func finish() {
            release?.resume(); release = nil
        }

        func cancel() {
            cancellations += 1
            release?.resume(throwing: CancellationError())
            release = nil
        }
    }

    private struct SlowProvider: UsageProvider {
        let gate: Gate
        let id = "slow"
        let name = "Slow"
        let isInstalled = true
        let logoAssetName = "ClaudeLogo"
        let authOptions: [AuthOption] = []
        let signInHint = ""

        func fetchUsage() async throws -> UsageSnapshot {
            try await gate.fetch()
            return UsageSnapshot(windows: [], fetchedAt: .now)
        }
    }

    @Test func hoverReschedulingJoinsTheCurrentFetchAndMaintenanceRunsOnce() async {
        let gate = Gate()
        let store = UsageStore(providers: [SlowProvider(gate: gate)], defaults: defaults)
        var maintenanceCalls = 0
        var completed: CheckedContinuation<Void, Never>?
        var nextMaintenance = Date.distantPast
        store.nextBackgroundRefresh = { nextMaintenance }
        store.backgroundRefresh = {
            maintenanceCalls += 1
            nextMaintenance = .distantFuture
            completed?.resume()
            completed = nil
        }
        store.reschedule()
        await gate.waitUntilStarted()
        for _ in 0 ..< 10 {
            store.setPanelOpen(true)
            store.setPanelOpen(false)
        }
        await withCheckedContinuation { continuation in
            completed = continuation
            Task { await gate.finish() }
        }
        store.suspend()
        #expect(await gate.calls == 1)
        #expect(await gate.cancellations == 0)
        #expect(maintenanceCalls == 1)
        #expect(store.entries.first?.state == .ok)
    }

    @Test func sleepCancelsMaintenanceAndWakeResumesThroughTheSameScheduler() async {
        let store = UsageStore(providers: [], defaults: defaults)
        let gate = Gate()
        var completed: CheckedContinuation<Void, Never>?
        var calls = 0
        var nextMaintenance = Date.distantPast
        store.nextBackgroundRefresh = { nextMaintenance }
        store.backgroundRefresh = {
            calls += 1
            if calls == 1 {
                try? await gate.fetch()
            } else {
                nextMaintenance = .distantFuture
            }
            completed?.resume()
            completed = nil
        }
        store.reschedule()
        await gate.waitUntilStarted()
        await withCheckedContinuation { continuation in
            completed = continuation
            store.suspend()
        }
        #expect(await gate.cancellations == 1)
        await withCheckedContinuation { continuation in
            completed = continuation
            store.resume()
        }
        store.suspend()
        #expect(calls == 2)
    }

    @Test func usageRefreshContinuesWhileMaintenanceIsBlocked() async {
        let provider = Gate()
        let maintenance = Gate()
        let store = UsageStore(providers: [SlowProvider(gate: provider)], defaults: defaults)
        defer { store.suspend() }
        var nextMaintenance = Date.distantPast
        store.nextBackgroundRefresh = { nextMaintenance }
        store.backgroundRefresh = {
            try? await maintenance.fetch()
            nextMaintenance = .distantFuture
        }
        store.reschedule()
        await provider.waitUntilStarted()
        await provider.finish()
        await maintenance.waitUntilStarted()

        store.refreshNow("slow")
        await provider.waitUntilStarted(after: 1)
        #expect(await provider.calls == 2)
        #expect(await maintenance.calls == 1)
        await provider.finish()
    }

    private struct InstantProvider: UsageProvider {
        let id = "instant"
        let name = "Instant"
        let isInstalled = true
        let logoAssetName = "ClaudeLogo"
        let authOptions: [AuthOption] = []
        let signInHint = ""
        let snapshot: UsageSnapshot

        func fetchUsage() async throws -> UsageSnapshot {
            snapshot
        }
    }

    @Test func aRelaunchKeepsTheNumbersAndDoesNotRefetch() async {
        let window = UsageWindow(id: "session", label: "5h", duration: 5 * 3600, usedFraction: 0.4, resetsAt: nil)
        let snapshot = UsageSnapshot(windows: [window], fetchedAt: Date(timeIntervalSince1970: 1_791_296_411))
        let first = UsageStore(providers: [InstantProvider(snapshot: snapshot)], defaults: defaults)
        await withCheckedContinuation { continuation in
            first.snapshotObserver = { _, _, _ in continuation.resume() }
            first.reschedule()
        }
        first.suspend()

        let relaunched = UsageStore(providers: [InstantProvider(snapshot: snapshot)], defaults: defaults)
        let entry = relaunched.entries[0]
        #expect(entry.snapshot == snapshot)
        #expect(entry.state == .ok)
        #expect(entry.schedule.nextDue(interval: 600) > .now)
    }

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
