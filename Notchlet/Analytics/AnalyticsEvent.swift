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
    case updateAvailable(fromVersion: String, toVersion: String)
    case updateInstallClicked(toVersion: String)
    case updateFailed(errorCode: Int)

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
        case .updateAvailable: "update_available"
        case .updateInstallClicked: "update_install_clicked"
        case .updateFailed: "update_failed"
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
        case let .historyOpened(scope):
            ["scope": scope]
        case let .updateAvailable(fromVersion, toVersion):
            ["from_version": fromVersion, "to_version": toVersion]
        case let .updateInstallClicked(toVersion):
            ["to_version": toVersion]
        case let .updateFailed(errorCode):
            ["error_code": errorCode]
        }
    }
}
