import CoreGraphics
import Foundation
@testable import Notchlet
import SwiftUI
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

    @Test func collapsedPanelHugsTheNotchAndSharesItsCenter() {
        let screen = CGRect(x: 0, y: 0, width: 3456, height: 2234)
        let notch = CGSize(width: 200, height: 32)
        let collapsed = NotchGeometry.panelFrame(
            screenFrame: screen,
            panelSize: NotchGeometry.collapsedPanelSize(notchSize: notch)
        )
        let expanded = NotchGeometry.panelFrame(screenFrame: screen)
        // Fillets on both sides, notch height, and the same horizontal
        // center as the expanded window so the drawn notch never shifts.
        #expect(collapsed.size == CGSize(width: 212, height: 32))
        #expect(collapsed.midX == expanded.midX)
        #expect(collapsed.maxY == expanded.maxY)
    }

    @Test func waitingNotchGrowsOnThreeSidesAndKeepsItsCenter() {
        let screen = CGRect(x: 0, y: 0, width: 3456, height: 2234)
        let notch = CGSize(width: 200, height: 32)
        let waiting = NotchGeometry.panelFrame(
            screenFrame: screen,
            panelSize: NotchGeometry.collapsedPanelSize(notchSize: notch, waiting: true)
        )
        let collapsed = NotchGeometry.panelFrame(
            screenFrame: screen,
            panelSize: NotchGeometry.collapsedPanelSize(notchSize: notch)
        )
        #expect(waiting.size == CGSize(width: 218, height: 35))
        #expect(waiting.midX == collapsed.midX)
        #expect(waiting.maxY == collapsed.maxY)
    }

    @Test func waitLineRunsStraightToTheTopEdgeInsideTheSides() {
        let rect = CGRect(x: 0, y: 0, width: 218, height: 35)
        let line = NotchShape.waitLine(in: rect, topRadius: 6, bottomRadius: 13, inset: 1.75)
        let bounds = line.boundingRect
        // Starts and ends on the top edge, 1.75 inside the straight sides
        // (which sit the fillet radius in from the rect), and never reaches
        // the fillets or the outer edge.
        #expect(bounds.minY == 0)
        #expect(bounds.minX == 7.75)
        #expect(bounds.maxX == 218 - 7.75)
        #expect(bounds.maxY == 35 - 1.75)
        #expect(line.currentPoint == CGPoint(x: 218 - 7.75, y: 0))
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

    @Test func primaryWindowIsTheShortestRegardlessOfUsage() {
        // The 5h session wins even when a longer window is far more used.
        let snapshot = UsageSnapshot(
            windows: [
                UsageWindow(id: "weekly", label: "Weekly", duration: 7 * 24 * 3600, usedFraction: 0.99, resetsAt: nil),
                UsageWindow(id: "session", label: "5h", duration: 5 * 3600, usedFraction: 0.0, resetsAt: nil),
            ],
            fetchedAt: .now
        )
        #expect(snapshot.primaryWindow?.id == "session")
    }

    @Test func expectedRemainingTracksTimeUntilReset() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let halfway = UsageWindow(
            id: "weekly", label: "Weekly", duration: 7 * 24 * 3600,
            usedFraction: 0.3, resetsAt: now.addingTimeInterval(3.5 * 24 * 3600)
        )
        #expect(halfway.expectedRemainingFraction(now: now) == 0.5)
        #expect(window(usedFraction: 0.3).expectedRemainingFraction(now: now) == nil)
    }
}
