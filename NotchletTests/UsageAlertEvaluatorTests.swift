import Foundation
@testable import Notchlet
import Testing

/// Once per window cycle, keyed on the reset time; crossing only when
/// there is none.
struct UsageAlertEvaluatorTests {
    private let now = Date(timeIntervalSince1970: 1_787_990_000)
    private let rule = UsageAlertRule(providerID: "claude-code", windowID: "session", percent: 80)

    private func snapshot(used: Double, resetsAt: Date?) -> UsageSnapshot {
        UsageSnapshot(
            windows: [UsageWindow(
                id: "session",
                label: "5h",
                duration: 5 * 3600,
                usedFraction: used,
                resetsAt: resetsAt
            )],
            fetchedAt: now
        )
    }

    private func firing(
        previous: UsageSnapshot?, current: UsageSnapshot, firedCycles: [String: Date] = [:]
    ) -> [UsageAlertNotice] {
        UsageAlertEvaluator.firing(
            rules: [rule], providerID: "claude-code",
            previous: previous, current: current, firedCycles: firedCycles, now: now
        )
    }

    @Test func firesAtTheMarkAndNotBelow() {
        let reset = now.addingTimeInterval(3600)
        #expect(firing(previous: nil, current: snapshot(used: 0.79, resetsAt: reset)).isEmpty)
        let fired = firing(previous: nil, current: snapshot(used: 0.8, resetsAt: reset))
        #expect(fired.map(\.rule) == [rule])
        #expect(fired.first?.window.usedFraction == 0.8)
    }

    @Test func firesOncePerCycleThenAgainAfterTheReset() {
        let reset = now.addingTimeInterval(3600)
        let sameCycle = [rule.key: reset.addingTimeInterval(20)]
        #expect(firing(previous: nil, current: snapshot(used: 0.95, resetsAt: reset), firedCycles: sameCycle).isEmpty)

        let nextReset = reset.addingTimeInterval(5 * 3600)
        #expect(firing(previous: nil, current: snapshot(used: 0.85, resetsAt: nextReset), firedCycles: sameCycle)
            .count == 1)
    }

    @Test func windowWithoutResetFiresOnTheCrossingOnly() {
        let below = snapshot(used: 0.5, resetsAt: nil)
        let above = snapshot(used: 0.9, resetsAt: nil)
        #expect(firing(previous: nil, current: above).isEmpty)
        #expect(firing(previous: below, current: above).count == 1)
        #expect(firing(previous: above, current: above).isEmpty)
    }

    @Test func otherProvidersAndWindowsAreIgnored() {
        let reset = now.addingTimeInterval(3600)
        let rules: Set<UsageAlertRule> = [
            rule,
            UsageAlertRule(providerID: "codex", windowID: "session", percent: 50),
            UsageAlertRule(providerID: "claude-code", windowID: "weekly", percent: 50),
        ]
        let fired = UsageAlertEvaluator.firing(
            rules: rules, providerID: "claude-code",
            previous: nil, current: snapshot(used: 1, resetsAt: reset), firedCycles: [:], now: now
        )
        #expect(fired.map(\.rule) == [rule])
    }
}

/// Persistence and the seeding that keeps a new rule quiet about a mark
/// the window already passed. A throwaway defaults suite so the real
/// setting is never touched.
struct UsageAlertsTests {
    private let now = Date(timeIntervalSince1970: 1_787_990_000)

    private func makeDefaults() -> UserDefaults {
        let name = "UsageAlertsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func snapshot(used: Double, resetsAt: Date?) -> UsageSnapshot {
        UsageSnapshot(
            windows: [UsageWindow(
                id: "session",
                label: "5h",
                duration: 5 * 3600,
                usedFraction: used,
                resetsAt: resetsAt
            )],
            fetchedAt: now
        )
    }

    @Test func aRuleAddedPastTheMarkWaitsForTheNextCycle() {
        let defaults = makeDefaults()
        let alerts = UsageAlerts(defaults: defaults)
        let rule = UsageAlertRule(providerID: "claude-code", windowID: "session", percent: 50)
        let reset = now.addingTimeInterval(3600)
        let past = snapshot(used: 0.7, resetsAt: reset)

        alerts.setRule(rule, on: true, window: past.windows[0])
        alerts.snapshotDidChange(
            providerID: "claude-code",
            previous: past,
            current: snapshot(used: 0.8, resetsAt: reset)
        )
        #expect(alerts.current == nil)

        let next = snapshot(used: 0.6, resetsAt: reset.addingTimeInterval(5 * 3600))
        alerts.snapshotDidChange(providerID: "claude-code", previous: past, current: next)
        #expect(alerts.current?.rule == rule)
    }

    @Test func noticesAndRulesSurviveARelaunchAndRemovalClearsBoth() {
        let defaults = makeDefaults()
        let rule = UsageAlertRule(providerID: "claude-code", windowID: "session", percent: 80)
        let reset = now.addingTimeInterval(3600)
        do {
            let alerts = UsageAlerts(defaults: defaults)
            alerts.setRule(rule, on: true, window: nil)
            alerts.snapshotDidChange(
                providerID: "claude-code",
                previous: nil,
                current: snapshot(used: 0.9, resetsAt: reset)
            )
            #expect(alerts.current?.rule == rule)
        }
        let relaunched = UsageAlerts(defaults: defaults)
        #expect(relaunched.isOn(rule))
        #expect(relaunched.current?.rule == rule)
        // The same cycle again does not queue a second notice.
        relaunched.snapshotDidChange(
            providerID: "claude-code",
            previous: nil,
            current: snapshot(used: 0.95, resetsAt: reset)
        )
        #expect(relaunched.state.pending.count == 1)

        relaunched.acknowledge()
        #expect(relaunched.current == nil)
        relaunched.setRule(rule, on: false, window: nil)
        #expect(!relaunched.isOn(rule))
        #expect(relaunched.state.firedCycles.isEmpty)
    }
}
