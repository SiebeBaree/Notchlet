import Foundation
@testable import Notchlet
import Testing

struct HistoryCopyTests {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    @Test func tokensScaleWithOneDecimalOnlyWhereItReads() {
        #expect(HistoryCopy.tokens(0) == "0")
        #expect(HistoryCopy.tokens(412) == "412")
        #expect(HistoryCopy.tokens(9800) == "9.8K")
        #expect(HistoryCopy.tokens(10000) == "10K")
        #expect(HistoryCopy.tokens(412_000) == "412K")
        #expect(HistoryCopy.tokens(1_234_567) == "1.2M")
        #expect(HistoryCopy.tokens(41_300_000) == "41.3M")
        #expect(HistoryCopy.tokens(120_000_000) == "120M")
        #expect(HistoryCopy.tokens(1_200_000_000) == "1.2B")
    }

    @Test func costKeepsCentsBelowAThousandDollars() {
        #expect(HistoryCopy.cost(0) == "$0.00")
        #expect(HistoryCopy.cost(0.004) == "<$0.01")
        #expect(HistoryCopy.cost(4.21) == "$4.21")
        #expect(HistoryCopy.cost(118.4) == "$118.40")
        #expect(HistoryCopy.cost(1204.4) == "$1,204")
    }

    @Test func daysReadTheSameEverywhere() {
        let day = TestSupport.day("2026-08-12")
        #expect(HistoryCopy.dayTitle(day, calendar: utc) == "Wed, Aug 12")
        #expect(HistoryCopy.shortDay(day, calendar: utc) == "Aug 12")
    }

    @Test func footerNamesTheGapsInOrder() {
        let graphStart = TestSupport.day("2025-09-01")
        #expect(HistoryCopy.footer(unpricedModels: [], coverageStart: nil, graphStart: graphStart, calendar: utc)
            == "Cost at API list prices")
        #expect(HistoryCopy.footer(
            unpricedModels: ["codex-auto-review"], coverageStart: TestSupport.day("2025-01-01"),
            graphStart: graphStart, calendar: utc
        ) == "Cost at API list prices · codex-auto-review not priced")
        #expect(HistoryCopy.footer(
            unpricedModels: ["a", "b", "c"], coverageStart: TestSupport.day("2026-07-24"),
            graphStart: graphStart, calendar: utc
        ) == "Cost at API list prices · a and 2 more not priced · History since Jul 24")
    }
}
