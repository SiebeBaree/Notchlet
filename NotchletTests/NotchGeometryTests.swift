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
    private func window(id: String = "session", usedFraction: Double) -> UsageWindow {
        UsageWindow(id: id, label: "5h", duration: 5 * 3600, usedFraction: usedFraction, resetsAt: nil)
    }

    @Test func remainingFractionIsClamped() {
        #expect(window(usedFraction: 0.25).remainingFraction == 0.75)
        #expect(window(usedFraction: 1.3).remainingFraction == 0)
        #expect(window(usedFraction: -0.1).remainingFraction == 1)
    }

    @Test func labelsDeriveFromDuration() {
        #expect(UsageWindow.label(forDuration: 5 * 3600) == "5h")
        #expect(UsageWindow.label(forDuration: 7 * 24 * 3600) == "Weekly")
        #expect(UsageWindow.label(forDuration: 30 * 24 * 3600) == "Monthly")
    }

    @Test func labelsTolerateNearMisses() {
        // The Codex CLI matches known windows with ±5% tolerance; mirror it.
        #expect(UsageWindow.label(forDuration: 29 * 24 * 3600) == "Monthly")
        #expect(UsageWindow.label(forDuration: 5 * 3600 + 300) == "5h")
        #expect(UsageWindow.label(forDuration: 3 * 24 * 3600) == "3d")
    }

    @Test func tightestWindowHasLeastRemaining() {
        let snapshot = UsageSnapshot(
            windows: [
                window(id: "a", usedFraction: 0.2),
                window(id: "b", usedFraction: 0.7),
                window(id: "c", usedFraction: 0.5),
            ],
            fetchedAt: .now
        )
        #expect(snapshot.tightestWindow?.id == "b")
    }
}
