import AppKit
import SwiftUI

/// Creates the notch panel, pins it over the notch and repositions it when
/// display configuration changes.
final class NotchWindowController: NSWindowController {
    init(store: UsageStore) {
        let panel = NotchPanel()
        super.init(window: panel)

        let screen = Self.targetScreen
        let notchSize = screen.map(Self.notchSize(of:)) ?? NotchGeometry.fallbackNotchSize
        panel.contentView = NSHostingView(rootView: NotchView(store: store, notchSize: notchSize))

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

    @objc private func reposition() {
        guard let screen = Self.targetScreen, let window else { return }
        window.setFrame(NotchGeometry.panelFrame(screenFrame: screen.frame), display: true)
    }
}
