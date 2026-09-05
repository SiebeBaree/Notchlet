import Foundation

/// Decides which rules fire on a fresh snapshot. Pure, so the once-per-cycle
/// logic is testable without a store.
nonisolated enum UsageAlertEvaluator {
    /// Two reset times this close apart are the same cycle: endpoints round
    /// or jitter the timestamp between fetches.
    static let cycleTolerance: TimeInterval = 60

    /// A rule fires when its window is at or past the threshold and it has
    /// not fired for this window cycle, the cycle being the window's reset
    /// time. A window without a reset time fires on the crossing only
    /// (previous fetch below, this one at or past), so it can never repeat.
    static func firing(
        rules: Set<UsageAlertRule>,
        providerID: String,
        previous: UsageSnapshot?,
        current: UsageSnapshot,
        firedCycles: [String: Date],
        now: Date
    ) -> [UsageAlertNotice] {
        rules.filter { $0.providerID == providerID }.compactMap { rule in
            guard let window = current.windows.first(where: { $0.id == rule.windowID }),
                  rule.matches(window)
            else { return nil }
            if let resetsAt = window.resetsAt {
                if let last = firedCycles[rule.key], isSameCycle(last, resetsAt) {
                    return nil
                }
            } else {
                guard let before = previous?.windows.first(where: { $0.id == rule.windowID }),
                      !rule.matches(before)
                else { return nil }
            }
            return UsageAlertNotice(rule: rule, window: window, firedAt: now)
        }
        .sorted { $0.rule.key < $1.rule.key }
    }

    static func isSameCycle(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) < cycleTolerance
    }
}
