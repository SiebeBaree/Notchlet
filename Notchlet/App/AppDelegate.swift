import AppKit

/// Owns the notch panel, the updater and analytics for the lifetime of the
/// app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: UsageStore?
    private var notchController: NotchWindowController?
    private var updateController: UpdateController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // As the unit tests' host app, don't touch credentials or the
        // network: the keychain permission prompt would hang the test runner.
        guard NSClassFromString("XCTestCase") == nil else { return }

        let store = UsageStore(providers: [
            ClaudeCodeUsageProvider(),
            CodexUsageProvider(),
        ])
        self.store = store
        store.startRefreshing()
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
        notchController = NotchWindowController(store: store, updater: updater)
        notchController?.showWindow(nil)

        Analytics.bootstrap()
        Analytics.startDailyHeartbeat { store.usagePressure }
    }

    @objc private func didWake() {
        store?.reschedule()
    }
}
