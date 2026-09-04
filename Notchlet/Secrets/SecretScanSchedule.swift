import Foundation

/// When a provider's chats get scanned. The first pass reads everything
/// the CLI has ever logged, so it waits until the Mac has been idle for two
/// minutes and is not hot; after that, once an hour over what changed,
/// which is small enough to run whatever the user is doing.
nonisolated enum SecretScanSchedule {
    static let launchDelay: TimeInterval = 5
    /// How often the loop looks at whether anything is due.
    static let tickInterval: TimeInterval = 300
    static let interval: TimeInterval = 3600
    static let idleRequirement: TimeInterval = 120

    enum Action: Equatable, Sendable {
        case full
        case incremental
        case wait
    }

    struct Conditions: Equatable, Sendable {
        var idleSeconds: TimeInterval
        var thermalState: ProcessInfo.ThermalState
    }

    static func action(lastScanAt: Date?, now: Date, conditions: Conditions) -> Action {
        guard let lastScanAt else {
            let calm = conditions.thermalState == .nominal || conditions.thermalState == .fair
            return conditions.idleSeconds >= idleRequirement && calm ? .full : .wait
        }
        return now.timeIntervalSince(lastScanAt) >= interval ? .incremental : .wait
    }
}
