import Foundation
@testable import Notchlet
import Testing

struct ClaudeCodeUsageProviderTests {
    /// Trimmed from a real /api/oauth/usage response.
    private let fixture = Data("""
    {
      "five_hour": { "utilization": 31.0, "resets_at": "2026-08-29T09:50:00.003920+00:00" },
      "seven_day": { "utilization": 0.0, "resets_at": "2026-09-05T09:00:01.003938+00:00" },
      "limits": [
        {
          "kind": "session", "group": "session", "percent": 31, "severity": "normal",
          "resets_at": "2026-08-29T09:50:00.003920+00:00", "scope": null, "is_active": true
        },
        {
          "kind": "weekly_all", "group": "weekly", "percent": 7, "severity": "normal",
          "resets_at": "2026-09-05T09:00:01.003938+00:00", "scope": null, "is_active": false
        },
        {
          "kind": "weekly_scoped", "group": "weekly", "percent": 52, "severity": "normal",
          "resets_at": "2026-09-05T09:00:00.004122+00:00",
          "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null },
          "is_active": false
        }
      ]
    }
    """.utf8)

    @Test func parsesAllThreeWindows() throws {
        let windows = try ClaudeCodeUsageProvider().parseWindows(from: fixture)

        #expect(windows.map(\.id) == ["session", "weekly", "weekly-fable"])
        #expect(windows.map(\.label) == ["5h", "Weekly", "Fable"])
        #expect(windows.map(\.usedFraction) == [0.31, 0.07, 0.52])
        #expect(windows[0].duration == 5 * 3600)
        #expect(windows[2].duration == 7 * 24 * 3600)
    }

    @Test func parsesMicrosecondResetDates() throws {
        let date = try #require(ClaudeCodeUsageProvider.parseDate("2026-08-29T09:50:00.003920+00:00"))
        let expected = try #require(ISO8601DateFormatter().date(from: "2026-08-29T09:50:00+00:00"))
        #expect(date == expected)
    }

    @Test func skipsUnknownLimitKinds() throws {
        let data = Data("""
        { "limits": [ { "kind": "daily_novel", "percent": 10, "resets_at": null, "scope": null } ] }
        """.utf8)
        #expect(try ClaudeCodeUsageProvider().parseWindows(from: data).isEmpty)
    }
}
