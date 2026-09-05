import AppKit
import notify

/// Builds every service at launch and keeps them alive for the life of the
/// app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: UsageStore?
    private var history: UsageHistory?
    private var scanner: SecretScanner?
    private var alerts: UsageAlerts?
    private var waits: AgentWaits?
    private var notchController: NotchWindowController?
    private var shareController: ShareEditorWindowController?
    private var updateController: UpdateController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // As the unit tests' host app, don't touch credentials or the
        // network: the keychain permission prompt would hang the test runner.
        guard NSClassFromString("XCTestCase") == nil else { return }

        // Order is the settings order, and the order installed CLIs claim
        // the active slots on first launch.
        let store = UsageStore(providers: [
            ClaudeCodeUsageProvider(),
            CodexUsageProvider(),
            CursorUsageProvider(),
            OpenCodeUsageProvider(),
        ])
        self.store = store
        store.reschedule()
        // History reads the CLIs' logs and seals finished days into the
        // archive, so it runs from first launch whether or not the pane is
        // ever opened.
        let history = UsageHistory(store: store)
        self.history = history
        history.start()
        // The same logs, scanned for leaked keys: once when the Mac is
        // idle, then hourly over what changed.
        let scanner = SecretScanner(store: store)
        self.scanner = scanner
        scanner.start()
        // Threshold alerts ride on the store's own refreshes: every
        // successful snapshot is checked against the rules, nothing polls.
        let alerts = UsageAlerts()
        self.alerts = alerts
        store.snapshotObserver = { [alerts] providerID, previous, current in
            alerts.snapshotDidChange(providerID: providerID, previous: previous, current: current)
        }
        // Agents that stopped or need an answer, told to us by the CLIs'
        // own hooks; the switch in settings installs those.
        let waits = AgentWaits { store.entries.filter(\.provider.isInstalled).map(\.id) }
        self.waits = waits
        waits.start()
        #if DEBUG
            // `notifyutil -p com.notchlet.debug.alert` while running from
            // Xcode shows an alert on the first window with data, to check
            // the card without waiting for real usage to cross a mark.
            var token: Int32 = 0
            notify_register_dispatch("com.notchlet.debug.alert", &token, .main) { _ in
                MainActor.assumeIsolated {
                    guard let entry = store.entries.first(where: { store.isEnabled($0.id) && $0.snapshot != nil }),
                          let window = entry.snapshot?.primaryWindow
                    else { return }
                    alerts.showTestNotice(providerID: entry.id, window: window)
                }
            }
        #endif
        // Refetch whatever came due during sleep instead of trusting a
        // slept-through timer.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        let updater = UpdateController()
        updateController = updater
        let shareController = ShareEditorWindowController(history: history)
        self.shareController = shareController
        notchController = NotchWindowController(
            store: store, history: history, updater: updater, scanner: scanner, alerts: alerts, waits: waits
        ) { scope in
            Analytics.capture(.shareOpened(scope: scope.rawValue))
            shareController.show(scope: scope)
        }
        notchController?.showWindow(nil)

        Analytics.bootstrap()
        Analytics.startDailyHeartbeat { store.usagePressure }
    }

    @objc private func didWake() {
        store?.reschedule()
        history?.reschedule()
        scanner?.reschedule()
    }
}
