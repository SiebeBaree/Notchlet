import Foundation

/// The first pass reads everything the CLI has ever logged, so it waits
/// for two idle minutes and a cool Mac; after that, hourly over what
/// changed.
nonisolated enum SecretScanSchedule {
    static let launchDelay: TimeInterval = 5
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
