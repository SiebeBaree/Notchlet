import CoreGraphics

/// Pure geometry for placing the panel around the notch.
/// Kept free of AppKit so it stays unit-testable.
enum NotchGeometry {
    /// Virtual notch used on displays without one, so the UI is fully
    /// developable and usable on external monitors.
    static let fallbackNotchSize = CGSize(width: 200, height: 32)

    /// Radius of the outward fillet where the notch meets the menu bar. The
    /// panel is drawn this much wider on each side so the straight edges stay
    /// aligned with the physical cutout.
    static let notchTopCornerRadius: CGFloat = 6

    /// Window size while the panel is expanded: a transparent window pinned
    /// to the top center of the screen, with room for the card to animate
    /// out of the notch.
    static let panelSize = CGSize(width: 640, height: 460)

    /// Window size while the panel is collapsed: exactly the notch
    /// silhouette including its outward fillets. The window shrinks to this
    /// when closed so cursor movement anywhere else never reaches the app
    /// and the window server has no larger transparent layer to composite.
    static func collapsedPanelSize(notchSize: CGSize) -> CGSize {
        CGSize(width: notchSize.width + 2 * notchTopCornerRadius, height: notchSize.height)
    }

    /// Frame for the panel in screen coordinates (origin at bottom-left,
    /// like AppKit): horizontally centered, flush with the top edge.
    static func panelFrame(screenFrame: CGRect, panelSize: CGSize = panelSize) -> CGRect {
        CGRect(
            x: (screenFrame.midX - panelSize.width / 2).rounded(),
            y: screenFrame.maxY - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }
}
