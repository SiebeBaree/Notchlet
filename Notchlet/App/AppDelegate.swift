import AppKit

/// Owns the notch panel for the lifetime of the app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = UsageStore(providers: [
            ClaudeCodeUsageProvider(),
            CodexUsageProvider(),
        ])
        notchController = NotchWindowController(store: store)
        notchController?.showWindow(nil)
    }
}
