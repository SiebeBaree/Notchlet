import Foundation
@testable import Notchlet
import Testing

struct UsageLedgerTests {
    private static func row(
        _ day: String,
        provider: String = "claude-code",
        model: String? = "claude-opus-5",
        input: Int = 0,
        output: Int,
        cost: Double? = nil
    ) -> DailyUsage {
        DailyUsage(
            day: TestSupport.day(day),
            providerID: provider,
            model: model,
            requests: 1,
            tokens: TokenCount(input: input, output: output),
            reportedCost: cost
        )
    }

    private let ledger = UsageLedger(rows: [
        Self.row("2026-09-01", output: 1_000_000),
        Self.row("2026-09-02", output: 2_000_000),
        Self.row("2026-09-02", provider: "codex", model: "gpt-5.6-sol", input: 1_000_000, output: 0),
        Self.row("2026-09-02", provider: "codex", model: "codex-auto-review", output: 10),
        Self.row("2026-09-03", provider: "opencode", model: "zen/mystery", output: 5, cost: 0.25),
    ])

    private let span = TestSupport.day("2026-09-02") ... TestSupport.day("2026-09-03")

    @Test func summaryCountsEveryTokenAndNamesWhatItCouldNotPrice() {
        let summary = ledger.summary(span)
        #expect(summary.requests == 4)
        #expect(summary.tokens == 3_000_015)
        #expect(summary.cost == 50 + 5 + 0.25)
        #expect(summary.unpricedModels == ["codex-auto-review"])
    }

    @Test func aSpanWithNothingPricedHasNoCost() {
        let summary = ledger.summary(TestSupport.day("2026-08-01") ... TestSupport.day("2026-08-31"))
        #expect(summary == UsageLedger.Summary())
    }

    @Test func modelsRankByTokens() {
        let models = ledger.models(span)
        #expect(models.map(\.model) == ["claude-opus-5", "gpt-5.6-sol", "codex-auto-review", "zen/mystery"])
        #expect(models[0].cost == 50)
        #expect(models[2].cost == nil)
        #expect(models[3].cost == 0.25)
        #expect(models[1].id == "codex/gpt-5.6-sol")
    }

    @Test func byDayKeepsEachDaysModels() throws {
        let days = ledger.byDay(span)
        #expect(Set(days.keys.map(\.string)) == ["2026-09-02", "2026-09-03"])
        let second = try #require(days[TestSupport.day("2026-09-02")])
        #expect(second.summary.tokens == 3_000_010)
        #expect(second.models.map(\.model) == ["claude-opus-5", "gpt-5.6-sol", "codex-auto-review"])
        #expect(second.summary.unpricedModels == ["codex-auto-review"])
    }
}
