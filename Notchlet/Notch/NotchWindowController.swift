import AppKit
import SwiftUI

/// Creates the notch panel, pins it over the notch and repositions it when
/// display configuration changes.
final class NotchWindowController: NSWindowController {
    private let store: UsageStore
    private let updater: UpdateController
    private let hostingView: NSHostingView<NotchView>
    private var notchSize: CGSize

    init(store: UsageStore, updater: UpdateController) {
        let panel = NotchPanel()
        let notchSize = Self.targetScreen.map(Self.notchSize(of:)) ?? NotchGeometry.fallbackNotchSize

        self.store = store
        self.updater = updater
        self.notchSize = notchSize
        hostingView = NSHostingView(rootView: NotchView(store: store, updater: updater, notchSize: notchSize))

        super.init(window: panel)
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

    /// Prefers the built-in display (the one with a notch), falls back to the
    /// main screen with a virtual notch.
    private static var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// Size of the physical notch, or the virtual fallback.
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

    /// Moves the panel onto the current target screen. The notch size is
    /// recomputed here too: unplugging a display can switch us between a
    /// physical notch and the virtual fallback, and the content has to follow.
    @objc private func reposition() {
        guard let screen = Self.targetScreen, let window else { return }
        window.setFrame(NotchGeometry.panelFrame(screenFrame: screen.frame), display: true)

        let currentNotchSize = Self.notchSize(of: screen)
        guard currentNotchSize != notchSize else { return }
        notchSize = currentNotchSize
        hostingView.rootView = NotchView(store: store, updater: updater, notchSize: currentNotchSize)
    }
}
