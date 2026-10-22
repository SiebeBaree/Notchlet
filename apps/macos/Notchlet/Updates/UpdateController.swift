import AppKit
import Sparkle

/// Sparkle behind the notch's gentle flow: a scheduled check never pops a
/// window, the notch shows an icon instead. An update Sparkle downloaded on
/// its own installs while nobody is looking, since Notchlet never quits
/// and Sparkle would otherwise wait a week for a quit before saying
/// anything; any other one hands off to Sparkle's standard install.
@Observable
final class UpdateController: NSObject {
    /// How long the Mac sits untouched before a downloaded update installs.
    static let idleRequirement: TimeInterval = 120

    /// Nil once the update got attention.
    private(set) var availableUpdateVersion: String?

    @ObservationIgnored private var updaterController: SPUStandardUpdaterController!
    /// Sparkle's handle to install the downloaded update and relaunch.
    @ObservationIgnored private var installDownloaded: (() -> Void)?
    /// Wakes the usage loop, which may be sleeping for minutes, so it starts
    /// watching for the idle moment.
    @ObservationIgnored var installBecameReady: (() -> Void)?

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            // A development build leaves it unstarted, which would otherwise
            // keep checking the feed on its own schedule even though the
            // manual check is blocked.
            startingUpdater: !DeviceInfo.isDevelopment,
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
        if let installDownloaded {
            installDownloaded()
        } else {
            updaterController.checkForUpdates(nil)
        }
    }

    /// When the usage loop should look again at a downloaded update: once
    /// the Mac could have been idle long enough.
    var nextInstallAt: Date? {
        guard installDownloaded != nil else { return nil }
        return .now.addingTimeInterval(max(0, Self.idleRequirement - UserPresence.idleSeconds))
    }

    /// Relaunches into the downloaded update unless someone could notice:
    /// the Mac in use, the notch open, or a line around it that a relaunch
    /// would drop.
    func installIfIdle(notchInUse: Bool) {
        guard let installDownloaded, !notchInUse, UserPresence.idleSeconds >= Self.idleRequirement else { return }
        installDownloaded()
    }

    /// Sparkle reports the result in its own UI.
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

extension UpdateController: SPUUpdaterDelegate {
    /// Taking the install keeps Sparkle from waiting for a quit.
    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        installDownloaded = immediateInstallHandler
        availableUpdateVersion = item.displayVersionString
        installBecameReady?()
        return true
    }

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
