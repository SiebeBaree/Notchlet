import Foundation
import Observation

/// Threshold alerts, checked on every refresh the usage store already
/// does, never on a timer of their own.
@Observable
final class UsageAlerts {
    static let defaultsKey = "usageAlerts"

    private let defaults: UserDefaults
    private let presence = UserPresence()
    private(set) var state: UsageAlertState
    private(set) var alertGeneration = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = Self.load(from: defaults) ?? UsageAlertState()
    }

    var rules: Set<UsageAlertRule> { state.rules }

    /// The newest notice nobody has acknowledged.
    var current: UsageAlertNotice? { state.pending.first }

    func isOn(_ rule: UsageAlertRule) -> Bool {
        state.rules.contains(rule)
    }

    /// A rule added to a window already past its mark is seeded with the
    /// current cycle, so it reports the next crossing rather than the one
    /// that already happened. Removing a rule takes its notice with it.
    func setRule(_ rule: UsageAlertRule, on: Bool, window: UsageWindow?) {
        if on {
            state.rules.insert(rule)
            if let window, rule.matches(window), let resetsAt = window.resetsAt {
                state.firedCycles[rule.key] = resetsAt
            }
        } else {
            state.rules.remove(rule)
            state.firedCycles[rule.key] = nil
            state.pending.removeAll { $0.rule == rule }
        }
        save()
        Analytics.capture(.usageAlertRuleChanged(
            provider: rule.providerID, window: rule.windowID, percent: rule.percent, enabled: on
        ))
    }

    func acknowledge() {
        guard !state.pending.isEmpty else { return }
        state.pending.removeFirst()
        save()
    }

    func snapshotDidChange(providerID: String, previous: UsageSnapshot?, current: UsageSnapshot) {
        let fired = UsageAlertEvaluator.firing(
            rules: state.rules,
            providerID: providerID,
            previous: previous,
            current: current,
            firedCycles: state.firedCycles,
            now: .now
        )
        guard !fired.isEmpty else { return }
        for notice in fired {
            state.firedCycles[notice.rule.key] = notice.window.resetsAt ?? notice.firedAt
            state.pending.removeAll { $0.rule == notice.rule }
            state.pending.insert(notice, at: 0)
            Analytics.capture(.usageAlertFired(
                provider: notice.rule.providerID, window: notice.rule.windowID, percent: notice.rule.percent
            ))
        }
        save()
        presence.whenActive { [weak self] in
            self?.alertGeneration += 1
        }
    }

    #if DEBUG
        /// 80% on the given window, for `DebugTrigger`. Not saved.
        func showTestNotice(providerID: String, window: UsageWindow) {
            let rule = UsageAlertRule(providerID: providerID, windowID: window.id, percent: 80)
            state.pending.removeAll { $0.rule == rule }
            state.pending.insert(UsageAlertNotice(rule: rule, window: window, firedAt: .now), at: 0)
            alertGeneration += 1
        }
    #endif

    private static func load(from defaults: UserDefaults) -> UsageAlertState? {
        guard let data = defaults.data(forKey: defaultsKey),
              let state = try? JSONDecoder().decode(UsageAlertState.self, from: data),
              state.version == UsageAlertState.currentVersion
        else { return nil }
        return state
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
