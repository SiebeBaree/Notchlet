import Foundation

/// One threshold on one rate-limit window. The set of these is the whole
/// setting.
nonisolated struct UsageAlertRule: Codable, Hashable, Sendable {
    static let percentChoices = [50, 75, 80, 90, 100]

    let providerID: String
    let windowID: String
    let percent: Int

    var key: String { "\(providerID)/\(windowID)/\(percent)" }

    /// Compared in fraction space: `80 / 100` is the same double as a
    /// provider's `0.8`, whereas `0.8 * 100` need not be exactly 80.
    func matches(_ window: UsageWindow) -> Bool {
        window.usedFraction >= Double(percent) / 100
    }
}

/// A rule that fired, with the window as it was. One per rule at most: a
/// later cycle replaces an unacknowledged notice rather than queueing.
nonisolated struct UsageAlertNotice: Codable, Equatable, Sendable, Identifiable {
    let rule: UsageAlertRule
    let window: UsageWindow
    let firedAt: Date

    var id: String { rule.key }
}

/// Persisted so a relaunch neither loses an alert nor repeats one.
nonisolated struct UsageAlertState: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = Self.currentVersion
    var rules: Set<UsageAlertRule> = []
    /// Newest first.
    var pending: [UsageAlertNotice] = []
    var firedCycles: [String: Date] = [:]
}
