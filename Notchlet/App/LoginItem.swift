import Foundation
import ServiceManagement

/// The notch is only there when the app runs, so Notchlet registers itself
/// as a login item once, ever: on a fresh install, and on the first launch
/// of an install that updated into this version. `seededKey` is what makes
/// it once, so a user who turns the setting off stays off.
enum LoginItem {
    private static let seededKey = "loginItemSeeded"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func seedIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        UserDefaults.standard.set(true, forKey: seededKey)
        #if DEBUG
        // Would launch the DerivedData build at every restart.
        #else
            setEnabled(true)
        #endif
    }

    /// Reports what the switch should show, which is not always what was
    /// asked for.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        guard enabled else {
            if service.status != .notRegistered {
                try? service.unregister()
            }
            return false
        }
        do {
            // Registering an already-registered app throws.
            if service.status != .enabled {
                try service.register()
            }
        } catch {
            return false
        }
        // The one state registering cannot fix: the user denied Notchlet
        // under Login Items, and only System Settings can undo that.
        guard service.status != .requiresApproval else {
            SMAppService.openSystemSettingsLoginItems()
            return false
        }
        return true
    }
}
