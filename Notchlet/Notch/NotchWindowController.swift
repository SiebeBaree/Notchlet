import AppKit
import SwiftUI

/// Pins the panel over the notch. The window is sized to the bare notch
/// while collapsed and grows to `panelSize` only while expanded: every
/// cursor move inside the window runs SwiftUI hover hit-testing, so the
/// window is never larger than what it draws.
final class NotchWindowController: NSWindowController {
    private let store: UsageStore
    private let history: UsageHistory
    private let updater: UpdateController
    private let scanner: SecretScanner
    private let alerts: UsageAlerts
    private let waits: AgentWaits
    private let share: (UsageHistory.Scope) -> Void
    private var notchSize: CGSize
    private var isExpanded = false
    private var isWaiting = false

    private lazy var hostingView = NSHostingView(rootView: makeRootView())

    init(
        store: UsageStore,
        history: UsageHistory,
        updater: UpdateController,
        scanner: SecretScanner,
        alerts: UsageAlerts,
        waits: AgentWaits,
        share: @escaping (UsageHistory.Scope) -> Void
    ) {
        let panel = NotchPanel()
        let notchSize = Self.targetScreen.map(Self.notchSize(of:)) ?? NotchGeometry.fallbackNotchSize

        self.store = store
        self.history = history
        self.updater = updater
        self.scanner = scanner
        self.alerts = alerts
        self.waits = waits
        self.share = share
        self.notchSize = notchSize

        super.init(window: panel)
        // The controller owns the frame, so the hosting view must not
        // publish an intrinsic size for AppKit to fit the window to.
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        reposition()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reposition),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The display with a notch, else the main screen with a virtual one.
    private static var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private static func notchSize(of screen: NSScreen) -> CGSize {
        let topInset = screen.safeAreaInsets.top
        guard topInset > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else {
            return NotchGeometry.fallbackNotchSize
        }
        return CGSize(width: screen.frame.width - left.width - right.width, height: topInset)
    }

    private func makeRootView() -> NotchView {
        NotchView(
            store: store,
            history: history,
            updater: updater,
            scanner: scanner,
            alerts: alerts,
            waits: waits,
            notchSize: notchSize,
            resizePanel: { [weak self] expanded, waiting in self?.setPanelState(expanded: expanded, waiting: waiting) },
            share: share
        )
    }

    /// The view calls this before it grows and after it has shrunk, so the
    /// drawing always has room.
    private func setPanelState(expanded: Bool, waiting: Bool) {
        guard expanded != isExpanded || waiting != isWaiting else { return }
        isExpanded = expanded
        isWaiting = waiting
        reposition()
    }

    private var panelSize: CGSize {
        isExpanded
            ? NotchGeometry.panelSize
            : NotchGeometry.collapsedPanelSize(notchSize: notchSize, waiting: isWaiting)
    }

    /// Unplugging a display can switch between a physical notch and the
    /// virtual fallback, so the notch size is recomputed here too.
    @objc private func reposition() {
        guard let screen = Self.targetScreen, let window else { return }
        let currentNotchSize = Self.notchSize(of: screen)
        if currentNotchSize != notchSize {
            notchSize = currentNotchSize
            // A fresh root view starts collapsed, so the window must too.
            isExpanded = false
            isWaiting = false
            hostingView.rootView = makeRootView()
        }
        window.setFrame(NotchGeometry.panelFrame(screenFrame: screen.frame, panelSize: panelSize), display: true)
    }
}
