import CoreGraphics

/// Placing the panel around the notch.
enum NotchGeometry {
    /// The virtual notch on displays without one.
    static let fallbackNotchSize = CGSize(width: 200, height: 32)

    /// The outward fillet where the notch meets the menu bar. The panel is
    /// drawn this much wider on each side so the straight edges stay
    /// aligned with the physical cutout.
    static let notchTopCornerRadius: CGFloat = 6

    /// How far the notch grows on each side and at the bottom while an
    /// agent waits: a 1pt black rim, the line, and half a point of black
    /// before the physical cutout.
    static let waitInset: CGFloat = 3
    static let waitLineWidth: CGFloat = 1.5
    /// From the grown edge to the centre of the line.
    static let waitLineInset: CGFloat = 1 + waitLineWidth / 2

    /// Room for the card to animate out of the notch.
    static let panelSize = CGSize(width: 640, height: 460)

    /// Exactly the silhouette including its fillets, plus the wait line's
    /// growth. The window shrinks to this when closed so cursor movement
    /// anywhere else never reaches the app.
    static func collapsedPanelSize(notchSize: CGSize, waiting: Bool = false) -> CGSize {
        let growth = waiting ? waitInset : 0
        return CGSize(
            width: notchSize.width + 2 * notchTopCornerRadius + 2 * growth,
            height: notchSize.height + growth
        )
    }

    /// Screen coordinates, origin at bottom-left like AppKit.
    static func panelFrame(screenFrame: CGRect, panelSize: CGSize = panelSize) -> CGRect {
        CGRect(
            x: (screenFrame.midX - panelSize.width / 2).rounded(),
            y: screenFrame.maxY - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }
}
