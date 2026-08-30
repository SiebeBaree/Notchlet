@testable import Notchlet
import Testing

struct AnalyticsEventTests {
    @Test func heartbeatMergesPressureBuckets() {
        let event = AnalyticsEvent.appHeartbeat(
            uptimeHours: 5.234,
            usagePressure: ["claude-code": "50-75", "codex": "0-25"]
        )

        let properties = event.properties
        #expect(event.name == "app_heartbeat")
        #expect(properties["uptime_hours"] as? Double == 5.2)
        #expect(properties["pressure_claude-code"] as? String == "50-75")
        #expect(properties["pressure_codex"] as? String == "0-25")
    }

    @Test func providerStateUsesSnakeCaseValues() {
        let event = AnalyticsEvent.providerStateChanged(provider: "codex", state: .notAvailable)

        #expect(event.properties["state"] as? String == "not_available")
        #expect(event.properties["provider"] as? String == "codex")
    }

    @Test func notchClosedRoundsDuration() {
        let event = AnalyticsEvent.notchClosed(openSeconds: 4.2467)

        #expect(event.properties["open_seconds"] as? Double == 4.2)
    }

    @Test func pressureBucketBoundaries() {
        #expect(UsageStore.pressureBucket(0) == "0-25")
        #expect(UsageStore.pressureBucket(0.25) == "25-50")
        #expect(UsageStore.pressureBucket(0.74) == "50-75")
        #expect(UsageStore.pressureBucket(1) == "75-100")
    }
}
