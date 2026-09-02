import AppKit

/// Borderless, non-activating panel that floats over the menu bar area and
/// stays put across spaces and full-screen apps.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovable = false
        isReleasedWhenClosed = false
    }

    /// Key is required: a mouse-down on the settings switches in a window
    /// that refuses key status collapses the panel instead of toggling.
    override var canBecomeKey: Bool { true }
}
