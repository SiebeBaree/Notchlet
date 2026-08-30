import AppKit
import Sparkle

/// Wraps Sparkle behind the notch's gentle update flow.
///
/// Scheduled checks run daily in the background and never pop a window.
/// When one finds an update, `availableUpdateVersion` is set and the notch
/// shows a small update icon; clicking it hands off to Sparkle's standard
/// download, verify, install and relaunch flow. Manual checks from settings
/// use the standard flow directly.
@Observable
final class UpdateController: NSObject {
    /// Version found by a scheduled background check, waiting for the user
    /// to notice the notch icon. Nil once the update got attention.
    private(set) var availableUpdateVersion: String?

    @ObservationIgnored private var updaterController: SPUStandardUpdaterController!

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }

    /// Persisted by Sparkle itself, seeded from SUEnableAutomaticChecks.
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    /// The user clicked the notch's update icon or install row.
    func installAvailableUpdate() {
        Analytics.capture(.updateInstallClicked(toVersion: availableUpdateVersion ?? "unknown"))
        updaterController.checkForUpdates(nil)
    }

    /// Manual check from settings; Sparkle reports the result in its own UI.
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

extension UpdateController: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Analytics.capture(.updateAvailable(
            fromVersion: DeviceInfo.appVersion,
            toVersion: item.displayVersionString
        ))
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let error = error as NSError
        // "No update found" and a cancelled install are not failures. The
        // feed 404ing before the repo is public lands here too.
        guard error.domain == SUSparkleErrorDomain,
              error.code != Int(Sparkle.SUError.noUpdateError.rawValue),
              error.code != Int(Sparkle.SUError.installationCanceledError.rawValue)
        else { return }
        Analytics.capture(.updateFailed(errorCode: error.code))
    }
}

extension UpdateController: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Never let Sparkle pop scheduled updates; the notch icon is the
        // whole reminder.
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if !state.userInitiated {
            availableUpdateVersion = update.displayVersionString
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableUpdateVersion = nil
    }
}
