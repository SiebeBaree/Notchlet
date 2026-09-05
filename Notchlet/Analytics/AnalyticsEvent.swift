import Foundation

/// Every analytics event Notchlet can send, with its properties typed at the
/// call site. Event names and property keys exist only here, so this file is
/// the complete catalog of what leaves the machine. Adding an event is adding
/// a case.
enum AnalyticsEvent {
    case appInstalled
    case appLaunched
    case appUpdated(fromVersion: String, toVersion: String)
    /// Fired once per calendar day while running. This is the load-bearing
    /// event: a login-item agent rarely relaunches, so DAU and retention come
    /// from heartbeats, not launches. `usagePressure` maps provider id to a
    /// usage bucket ("0-25"..."75-100"), never real numbers.
    case appHeartbeat(uptimeHours: Double, usagePressure: [String: String])
    case notchOpened
    case notchClosed(openSeconds: TimeInterval)
    /// Only fired on transitions between states, never per refresh.
    case providerStateChanged(provider: String, state: UsageStore.ProviderState)
    case settingsOpened
    /// `scope` is "all" or a provider id.
    case historyOpened(scope: String)
    /// Booleans and enum values only, never free text.
    case settingChanged(key: String, value: String)
    /// `scope` is "all" or a provider id.
    case shareOpened(scope: String)
    /// What left the app and how it was configured, never the numbers on it.
    case shareExported(method: String, theme: String, period: String, graph: String, cost: Bool, models: Bool)
    case updateAvailable(fromVersion: String, toVersion: String)
    case updateInstallClicked(toVersion: String)
    case updateFailed(errorCode: Int)
    /// Counts only: raw matches in the scan and distinct secrets not seen
    /// before. `kind` is "full" or "hourly".
    case secretScanCompleted(provider: String, kind: String, findings: Int, new: Int, seconds: TimeInterval)
    /// The one place a fragment of chat content leaves the machine, on an
    /// explicit click: the first six and last two characters of a match the
    /// user says is not a secret, so a noisy rule can be turned off.
    case secretFalsePositive(provider: String, rule: String, preview: String, length: Int)
    case secretIgnored(provider: String, rule: String)
    case secretHelpOpened(provider: String, rule: String)
    /// Thresholds only, never the usage number that crossed them.
    case usageAlertRuleChanged(provider: String, window: String, percent: Int, enabled: Bool)
    case usageAlertFired(provider: String, window: String, percent: Int)
    /// The provider and whether it finished or needs input; never the
    /// session, the directory or the app it runs in.
    case agentWaitShown(provider: String, kind: String)
    /// What made the line go: "hover", "focus" or "prompt".
    case agentWaitCleared(by: String)

    var name: String {
        switch self {
        case .appInstalled: "app_installed"
        case .appLaunched: "app_launched"
        case .appUpdated: "app_updated"
        case .appHeartbeat: "app_heartbeat"
        case .notchOpened: "notch_opened"
        case .notchClosed: "notch_closed"
        case .providerStateChanged: "provider_state_changed"
        case .settingsOpened: "settings_opened"
        case .historyOpened: "history_opened"
        case .settingChanged: "setting_changed"
        case .shareOpened: "share_opened"
        case .shareExported: "share_exported"
        case .updateAvailable: "update_available"
        case .updateInstallClicked: "update_install_clicked"
        case .updateFailed: "update_failed"
        case .secretScanCompleted: "secret_scan_completed"
        case .secretFalsePositive: "secret_false_positive"
        case .secretIgnored: "secret_ignored"
        case .secretHelpOpened: "secret_help_opened"
        case .usageAlertRuleChanged: "usage_alert_rule_changed"
        case .usageAlertFired: "usage_alert_fired"
        case .agentWaitShown: "agent_wait_shown"
        case .agentWaitCleared: "agent_wait_cleared"
        }
    }

    var properties: [String: Any] {
        switch self {
        case .appInstalled, .appLaunched, .notchOpened, .settingsOpened:
            [:]
        case let .appUpdated(fromVersion, toVersion):
            ["from_version": fromVersion, "to_version": toVersion]
        case let .appHeartbeat(uptimeHours, usagePressure):
            usagePressure.reduce(into: ["uptime_hours": (uptimeHours * 10).rounded() / 10]) {
                $0["pressure_\($1.key)"] = $1.value
            }
        case let .notchClosed(openSeconds):
            ["open_seconds": (openSeconds * 10).rounded() / 10]
        case let .providerStateChanged(provider, state):
            ["provider": provider, "state": state.rawValue]
        case let .settingChanged(key, value):
            ["key": key, "value": value]
        case let .historyOpened(scope), let .shareOpened(scope):
            ["scope": scope]
        case let .shareExported(method, theme, period, graph, cost, models):
            ["method": method, "theme": theme, "period": period, "graph": graph, "cost": cost, "models": models]
        case let .updateAvailable(fromVersion, toVersion):
            ["from_version": fromVersion, "to_version": toVersion]
        case let .updateInstallClicked(toVersion):
            ["to_version": toVersion]
        case let .updateFailed(errorCode):
            ["error_code": errorCode]
        case let .secretScanCompleted(provider, kind, findings, new, seconds):
            [
                "provider": provider,
                "kind": kind,
                "findings": findings,
                "new": new,
                "seconds": (seconds * 10).rounded() / 10,
            ]
        case let .secretFalsePositive(provider, rule, preview, length):
            ["provider": provider, "rule": rule, "preview": preview, "length": length]
        case let .secretIgnored(provider, rule), let .secretHelpOpened(provider, rule):
            ["provider": provider, "rule": rule]
        case let .usageAlertRuleChanged(provider, window, percent, enabled):
            ["provider": provider, "window": window, "percent": percent, "enabled": enabled]
        case let .usageAlertFired(provider, window, percent):
            ["provider": provider, "window": window, "percent": percent]
        case let .agentWaitShown(provider, kind):
            ["provider": provider, "kind": kind]
        case let .agentWaitCleared(by):
            ["by": by]
        }
    }
}
