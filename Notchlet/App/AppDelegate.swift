import AppKit

/// Builds every service at launch and keeps them alive for the life of the
/// app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private struct Services {
        let store: UsageStore
        let history: UsageHistory
        let scanner: SecretScanner
        let alerts: UsageAlerts
        let waits: AgentWaits
        let updater: UpdateController
        let shareController: ShareEditorWindowController
        let notchController: NotchWindowController
    }

    private var services: Services?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // As the tests' host app, stay away from credentials and the
        // network: the keychain prompt would hang the test runner.
        guard NSClassFromString("XCTestCase") == nil else { return }
        let services = Self.makeServices()
        self.services = services
        services.store.reschedule()
        services.history.start()
        services.scanner.start()
        services.waits.start()
        services.notchController.showWindow(nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        Analytics.bootstrap()
        Analytics.startDailyHeartbeat { services.store.usagePressure }
        #if DEBUG
            DebugTrigger.listen(.init(
                store: services.store, scanner: services.scanner, alerts: services.alerts, waits: services.waits
            ))
        #endif
    }

    private static func makeServices() -> Services {
        // Settings order, and the order installed CLIs claim the active slots.
        let store = UsageStore(providers: [
            ClaudeCodeUsageProvider(),
            CodexUsageProvider(),
            CursorUsageProvider(),
            OpenCodeUsageProvider(),
        ])
        let history = UsageHistory(store: store)
        let scanner = SecretScanner(store: store)
        let alerts = UsageAlerts()
        store.snapshotObserver = { [alerts] providerID, previous, current in
            alerts.snapshotDidChange(providerID: providerID, previous: previous, current: current)
        }
        let waits = AgentWaits { store.entries.filter(\.provider.isInstalled).map(\.id) }
        let updater = UpdateController()
        let shareController = ShareEditorWindowController(history: history)
        let notchController = NotchWindowController(
            store: store, history: history, updater: updater, scanner: scanner, alerts: alerts, waits: waits
        ) { scope in
            Analytics.capture(.shareOpened(scope: scope.rawValue))
            shareController.show(scope: scope)
        }
        return Services(
            store: store, history: history, scanner: scanner, alerts: alerts, waits: waits,
            updater: updater, shareController: shareController, notchController: notchController
        )
    }

    @objc private func didWake() {
        services?.store.reschedule()
        services?.history.reschedule()
        services?.scanner.reschedule()
    }
}
