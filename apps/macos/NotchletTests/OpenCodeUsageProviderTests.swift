import Foundation
@testable import Notchlet
import Testing

struct OpenCodeUsageProviderTests {
    /// Shape of /zen/go/v1/usage: `percent` is a whole number, `resetsAt`
    /// is absolute with millisecond precision.
    private let fixture = Data("""
    {
      "usage": {
        "rolling": { "status": "ok", "percent": 12, "resetsAt": "2026-07-12T13:30:00.662Z" },
        "weekly": { "status": "ok", "percent": 8, "resetsAt": "2026-07-13T00:00:00.662Z" },
        "monthly": { "status": "rate-limited", "percent": 100, "resetsAt": "2026-08-04T11:18:32.662Z" }
      }
    }
    """.utf8)

    @Test func parsesAllThreeWindows() throws {
        let windows = try OpenCodeUsageProvider().parseWindows(from: fixture)

        #expect(windows.map(\.id) == ["rolling", "weekly", "monthly"])
        #expect(windows.map(\.label) == ["5h", "Weekly", "Monthly"])
        #expect(windows.map(\.usedFraction) == [0.12, 0.08, 1.0])
        #expect(windows[0].duration == 5 * 3600)
        #expect(windows[0].resetsAt == ISO8601DateFormatter().date(from: "2026-07-12T13:30:00Z"))
        #expect(windows[2].remainingFraction == 0)
    }

    @Test func rollingWindowIsTheSummaryGauge() throws {
        let windows = try OpenCodeUsageProvider().parseWindows(from: fixture)
        #expect(UsageSnapshot(windows: windows, fetchedAt: .now).primaryWindow?.id == "rolling")
    }

    @Test func skipsMissingWindows() throws {
        let data = Data("""
        { "usage": { "weekly": { "status": "ok", "percent": 40, "resetsAt": "2026-07-13T00:00:00Z" } } }
        """.utf8)
        let windows = try OpenCodeUsageProvider().parseWindows(from: data)
        #expect(windows.map(\.id) == ["weekly"])
    }
}
