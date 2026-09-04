import AppKit

/// Owns the notch panel, the updater and analytics for the lifetime of the
/// app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: UsageStore?
    private var history: UsageHistory?
    private var scanner: SecretScanner?
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
        store.startRefreshing()
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
            store: store, history: history, updater: updater, scanner: scanner
        ) { scope in
            Analytics.capture(.shareOpened(scope: scope.storedValue))
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
