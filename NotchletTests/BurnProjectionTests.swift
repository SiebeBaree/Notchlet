import Foundation
@testable import Notchlet
import Testing

struct BurnProjectionTests {
    private let now = Date(timeIntervalSince1970: 1_787_990_000)
    private let fiveHours: TimeInterval = 5 * 3600

    /// Projects a 5-hour window with `hoursLeft` until reset, so elapsed is
    /// 5h minus that.
    private func project(used: Double, hoursLeft: Double) -> BurnProjection? {
        BurnProjection.project(
            usedFraction: used,
            resetsAt: now.addingTimeInterval(hoursLeft * 3600),
            windowDuration: fiveHours,
            now: now
        )
    }

    @Test func staleOrMissingResetGivesNothing() {
        #expect(BurnProjection.project(usedFraction: 0.5, resetsAt: nil, windowDuration: fiveHours, now: now) == nil)
        let past = now.addingTimeInterval(-60)
        #expect(BurnProjection.project(usedFraction: 0.5, resetsAt: past, windowDuration: fiveHours, now: now) == nil)
    }

    @Test func freshWindowIsPlenty() {
        // 100% left mid-window: flat usage, no depletion claim.
        #expect(project(used: 0, hoursLeft: 2) == BurnProjection(verdict: .plenty, depletionDate: nil))
    }

    @Test func earlyWindowBurstIsStillPlenty() {
        // 3% burned in the first 12 minutes (4% of the window) extrapolates
        // to "empty way early", but inside the grace period we don't judge.
        #expect(project(used: 0.03, hoursLeft: 4.8) == BurnProjection(verdict: .plenty, depletionDate: nil))
    }

    @Test func fastBurnDepletesEarly() throws {
        // 60% burned in the first hour: empty in ~40 min, reset in 4h.
        let projection = project(used: 0.6, hoursLeft: 4)
        #expect(projection?.verdict == .early)
        let depletion = try #require(projection?.depletionDate)
        #expect(abs(depletion.timeIntervalSince(now) - 40 * 60) < 60)
    }

    @Test func matchedBurnIsOnPace() {
        // Half burned at half the window: empty right at the reset.
        #expect(project(used: 0.5, hoursLeft: 2.5)?.verdict == .onPace)
    }

    @Test func slowBurnMeansPlenty() {
        // 20% burned with an hour left: pace outlasts the reset comfortably.
        let projection = project(used: 0.2, hoursLeft: 1)
        #expect(projection?.verdict == .plenty)
        #expect(projection?.depletionDate != nil)
    }
}
