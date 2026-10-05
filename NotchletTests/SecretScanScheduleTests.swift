import Foundation
@testable import Notchlet
import Testing

struct SecretScanScheduleTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func conditions(idle: TimeInterval = 600, thermal: ProcessInfo.ThermalState = .nominal)
        -> SecretScanSchedule.Conditions
    {
        SecretScanSchedule.Conditions(idleSeconds: idle, thermalState: thermal)
    }

    @Test func firstScanWaitsForAnIdleCoolMac() {
        #expect(SecretScanSchedule.action(lastScanAt: nil, now: now, conditions: conditions()) == .full)
        #expect(SecretScanSchedule.action(lastScanAt: nil, now: now, conditions: conditions(idle: 30)) == .wait)
        #expect(SecretScanSchedule.action(lastScanAt: nil, now: now, conditions: conditions(thermal: .fair)) == .full)
        #expect(SecretScanSchedule
            .action(lastScanAt: nil, now: now, conditions: conditions(thermal: .serious)) == .wait)
    }

    @Test func laterScansRespectPowerAndThermalConditionsWithoutIndefiniteDeferral() {
        let recent = now.addingTimeInterval(-600)
        let old = now.addingTimeInterval(-3600)
        #expect(SecretScanSchedule.action(lastScanAt: recent, now: now, conditions: conditions(idle: 0)) == .wait)
        #expect(SecretScanSchedule.action(
            lastScanAt: old,
            now: now,
            conditions: conditions(idle: 0, thermal: .critical)
        ) == .wait)
        #expect(SecretScanSchedule.action(lastScanAt: old, now: now, conditions: conditions(idle: 0)) == .incremental)
        let lowPower = SecretScanSchedule.Conditions(idleSeconds: 600, thermalState: .nominal, isLowPowerMode: true)
        #expect(SecretScanSchedule.action(lastScanAt: nil, now: now, conditions: lowPower) == .wait)
        #expect(SecretScanSchedule.action(lastScanAt: old, now: now, conditions: lowPower) == .wait)
        #expect(SecretScanSchedule
            .action(lastScanAt: now.addingTimeInterval(-7200), now: now, conditions: lowPower) == .incremental)
        #expect(SecretScanSchedule.action(lastScanAt: now.addingTimeInterval(-7200), now: now,
                                          conditions: conditions(thermal: .critical)) == .wait)
    }
}
