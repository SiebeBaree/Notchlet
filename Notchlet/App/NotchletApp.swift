import SwiftUI

@main
struct NotchletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Notchlet lives in the notch. There is no main window and no dock
        // icon (LSUIElement). Settings is the only standard scene.
        Settings {
            SettingsView()
        }
    }
}
