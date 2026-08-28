import CoreGraphics
@testable import Notchlet
import Testing

struct NotchGeometryTests {
    @Test func panelFrameIsTopCentered() {
        let frame = NotchGeometry.panelFrame(
            screenFrame: CGRect(x: 0, y: 0, width: 3456, height: 2234),
            panelSize: CGSize(width: 640, height: 260)
        )
        #expect(frame == CGRect(x: 1408, y: 1974, width: 640, height: 260))
    }

    @Test func panelFrameRespectsScreenOrigin() {
        // A secondary display positioned to the right of the main one.
        let frame = NotchGeometry.panelFrame(
            screenFrame: CGRect(x: 3456, y: 500, width: 1920, height: 1080),
            panelSize: CGSize(width: 600, height: 200)
        )
        #expect(frame == CGRect(x: 4116, y: 1380, width: 600, height: 200))
    }
}

struct UsageWindowTests {
    @Test func remainingFractionIsClamped() {
        #expect(UsageWindow(usedFraction: 0.25).remainingFraction == 0.75)
        #expect(UsageWindow(usedFraction: 1.3).remainingFraction == 0)
        #expect(UsageWindow(usedFraction: -0.1).remainingFraction == 1)
    }
}
