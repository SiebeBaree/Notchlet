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

    @Test func laterScansAreHourlyWhateverTheUserIsDoing() {
        let recent = now.addingTimeInterval(-600)
        let old = now.addingTimeInterval(-3600)
        #expect(SecretScanSchedule.action(lastScanAt: recent, now: now, conditions: conditions(idle: 0)) == .wait)
        #expect(SecretScanSchedule.action(
            lastScanAt: old,
            now: now,
            conditions: conditions(idle: 0, thermal: .critical)
        ) == .incremental)
    }
}
