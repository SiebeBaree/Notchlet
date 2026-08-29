import AppKit

/// Owns the notch panel, the updater and analytics for the lifetime of the
/// app.
final class AppDelegate: NSObject, NSApplicationDelegate {
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
        store.startRefreshing()

        let updater = UpdateController()
        updateController = updater
        notchController = NotchWindowController(store: store, updater: updater)
        notchController?.showWindow(nil)

        Analytics.bootstrap()
        Analytics.startDailyHeartbeat { store.usagePressure }
    }
}
