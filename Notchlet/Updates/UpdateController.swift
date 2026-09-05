import AppKit
import Sparkle

/// Sparkle behind the notch's gentle flow: a scheduled check never pops a
/// window, the notch shows an icon instead, and clicking it hands off to
/// Sparkle's standard install.
@Observable
final class UpdateController: NSObject {
    /// Nil once the update got attention.
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

    func installAvailableUpdate() {
        Analytics.capture(.updateInstallClicked(toVersion: availableUpdateVersion ?? "unknown"))
        updaterController.checkForUpdates(nil)
    }

    /// Sparkle reports the result in its own UI.
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
        // "No update found" and a cancelled install are not failures.
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
