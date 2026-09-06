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

    /// `.requiresApproval` is registered too, waiting on the user.
    private static var isRegistered: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    static func seedIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        #if DEBUG
        // Would launch the DerivedData build at every restart, and the
        // marker lives in the defaults the release build reads.
        #else
            if !isRegistered {
                try? SMAppService.mainApp.register()
            }
            // Not marking a failure is what makes the next launch retry.
            guard isRegistered else { return }
            UserDefaults.standard.set(true, forKey: seededKey)
        #endif
    }

    /// Reports what the switch should show, which is the status after the
    /// attempt, not what was asked for.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        guard enabled else {
            if service.status != .notRegistered {
                try? service.unregister()
            }
            return service.status == .enabled
        }
        if !isRegistered {
            // Registering an already-registered app throws.
            try? service.register()
        }
        // The one state registering cannot fix: the user denied Notchlet
        // under Login Items, and only System Settings can undo that.
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        return service.status == .enabled
    }
}
