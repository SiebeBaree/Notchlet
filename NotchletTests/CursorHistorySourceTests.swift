import Foundation
@testable import Notchlet
import Testing

struct CursorHistorySourceTests {
    @Test func parsesTheExportIntoOneEventPerRow() throws {
        let csv = """
        Date,Kind,Model,Max Mode,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,Total Tokens,Cost
        2026-09-03T06:21:46.561Z,Included in Pro,claude-4.5-sonnet-thinking,No,"1,200",300,"10,000",450,"11,950",Included
        2026-09-02 10:00:00,Included in Pro,"GPT-5.6 Sol (Auto, high)",No,,0,,20,20,Included
        2026-09-01T10:00:00Z,Errored,composer-2,No,broken,0,0,0,0,Included
        """
        let events = try CursorHistorySource.events(fromCSV: csv)

        #expect(events.count == 2)
        #expect(events[0].model == "claude-sonnet-4-5")
        #expect(events[0].timestamp == ISO8601DateFormatter().date(from: "2026-09-03T06:21:46Z"))
        #expect(events[0].tokens == TokenCount(input: 300, cacheRead: 10000, cacheWrite5m: 1200, output: 450))
        #expect(events[1].model == "gpt-5.6-sol")
        #expect(events[1].timestamp == ISO8601DateFormatter().date(from: "2026-09-02T10:00:00Z"))
        #expect(events[1].tokens == TokenCount(output: 20))
        #expect(events.allSatisfy { $0.reportedCost == nil && $0.id == nil })
    }

    @Test func anExportWithoutTheTokenColumnsIsRefused() throws {
        #expect(throws: ProviderError.self) {
            try CursorHistorySource.events(fromCSV: "Date,Model,Cost\n2026-09-03T06:21:46Z,auto,1\n")
        }
        #expect(try CursorHistorySource.events(fromCSV: "").isEmpty)
    }

    @Test func cursorLabelsFoldToTheVendorsIds() {
        #expect(CursorModelNames.canonical("claude-4.5-sonnet-thinking") == "claude-sonnet-4-5")
        #expect(CursorModelNames.canonical("claude-4.6-opus-high-thinking-fast") == "claude-opus-4-6-fast")
        #expect(CursorModelNames.canonical("claude-opus-4-7-thinking-max") == "claude-opus-4-7")
        #expect(CursorModelNames.canonical("claude-fable-5.1-high") == "claude-fable-5-1")
        #expect(CursorModelNames.canonical("claude-4-sonnet") == "claude-sonnet-4")
        #expect(CursorModelNames.canonical("gpt-5.6-sol-xhigh") == "gpt-5.6-sol")
        #expect(CursorModelNames.canonical("gpt-5.4-high-fast") == "gpt-5.4-fast")
        #expect(CursorModelNames.canonical("composer-2.5") == "composer-2.5")
        #expect(CursorModelNames.canonical("auto") == "auto")
        #expect(CursorModelNames.canonical("Claude Opus 4.5 (Max)") == "claude-opus-4-5")
        #expect(CursorModelNames.canonical("max") == "max")
    }

    @Test func csvHandlesQuotesAndLineEndings() {
        let rows = CSV.rows("a,\"b, c\",\"say \"\"hi\"\"\"\r\n1,,3\n")
        #expect(rows == [["a", "b, c", "say \"hi\""], ["1", "", "3"]])
        #expect(CSV.rows("").isEmpty)
        #expect(CSV.rows("x") == [["x"]])
    }
}
