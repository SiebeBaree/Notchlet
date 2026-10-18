@testable import Notchlet
import Testing

struct AnalyticsEventTests {
    @Test func heartbeatRoundsUptime() {
        let event = AnalyticsEvent.appHeartbeat(uptimeHours: 5.234)

        #expect(event.name == "app_heartbeat")
        #expect(event.properties["uptime_hours"] as? Double == 5.2)
    }

    @Test func providerStateUsesSnakeCaseValues() {
        let event = AnalyticsEvent.providerStateChanged(provider: "codex", state: .notAvailable(.expired))

        #expect(event.properties["state"] as? String == "not_available")
        #expect(event.properties["provider"] as? String == "codex")
    }

    @Test func notchClosedRoundsDuration() {
        let event = AnalyticsEvent.notchClosed(openSeconds: 4.2467)

        #expect(event.properties["open_seconds"] as? Double == 4.2)
    }
}
