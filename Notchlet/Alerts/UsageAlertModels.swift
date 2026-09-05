import Foundation

/// One threshold on one rate-limit window: "Claude Code, 5h, 80% used".
/// The set of these is the whole setting; several on one window are fine.
nonisolated struct UsageAlertRule: Codable, Hashable, Sendable {
    /// The percentages the settings chips offer.
    static let percentChoices = [50, 75, 80, 90, 100]

    let providerID: String
    let windowID: String
    /// Used percentage that fires the alert.
    let percent: Int

    /// Stable key for the fired-cycle map and for analytics.
    var key: String { "\(providerID)/\(windowID)/\(percent)" }

    /// Compared in fraction space: `80 / 100` is the same double as a
    /// provider's `0.8`, whereas `0.8 * 100` need not be exactly 80.
    func matches(_ window: UsageWindow) -> Bool {
        window.usedFraction >= Double(percent) / 100
    }
}

/// A rule that fired, with the window as it was at that moment. One per
/// rule at most: a rule firing again in a later cycle replaces its
/// unacknowledged notice rather than queueing behind it.
nonisolated struct UsageAlertNotice: Codable, Equatable, Sendable, Identifiable {
    let rule: UsageAlertRule
    let window: UsageWindow
    let firedAt: Date

    var id: String { rule.key }
}

/// What persists between launches: the rules, the notices nobody has
/// acknowledged yet, and the reset time of the cycle each rule last fired
/// in, so a relaunch neither loses an alert nor repeats one.
nonisolated struct UsageAlertState: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = Self.currentVersion
    var rules: Set<UsageAlertRule> = []
    /// Newest first.
    var pending: [UsageAlertNotice] = []
    var firedCycles: [String: Date] = [:]
}
