import Foundation
@testable import Notchlet
import Testing

struct ModelPricesTests {
    @Test func normalizesVendorPrefixesTagsAndDates() {
        #expect(ModelPrices.normalize("claude-sonnet-4-5-20250929") == "claude-sonnet-4-5")
        #expect(ModelPrices.normalize("anthropic/claude-opus-5[1m]") == "claude-opus-5")
        #expect(ModelPrices.normalize("openai/gpt-5.4-2026-03-05") == "gpt-5.4")
        #expect(ModelPrices.normalize("Claude-Haiku-4-5-20251001") == "claude-haiku-4-5")
        #expect(ModelPrices.normalize("claude-opus-4-5@20251101") == "claude-opus-4-5")
        #expect(ModelPrices.normalize("gpt-5.6-sol") == "gpt-5.6-sol")
    }

    @Test func anthropicRatesFollowTheCacheMultipliers() throws {
        let price = try #require(ModelPrices.price(for: "claude-opus-5"))
        #expect(price.input == 5)
        #expect(price.output == 25)
        #expect(price.cacheRead == 0.5)
        #expect(price.cacheWrite5m == 6.25)
        #expect(price.cacheWrite1h == 10)

        let tokens = TokenCount(
            input: 1_000_000,
            cacheRead: 1_000_000,
            cacheWrite5m: 1_000_000,
            cacheWrite1h: 1_000_000,
            output: 1_000_000
        )
        #expect(price.cost(of: tokens) == 46.75)
    }

    @Test func openAICacheWritesAreOrdinaryInput() throws {
        let price = try #require(ModelPrices.price(for: "gpt-5.6-sol"))
        #expect(price.cacheWrite5m == price.input)
        #expect(price.cost(of: TokenCount(input: 2_000_000, cacheRead: 1_000_000, output: 100_000)) == 13.5)
    }

    @Test func unknownModelsStayUnpriced() {
        #expect(ModelPrices.price(for: "codex-auto-review") == nil)
        #expect(ModelPrices.price(for: "gpt-5.7-mini") == nil)
        #expect(ModelPrices.price(for: "") == nil)
    }

    @Test func aReportedCostBeatsTheTable() throws {
        let priced = try DailyUsage(
            day: #require(DayKey("2026-09-01")),
            providerID: "p",
            model: "claude-opus-5",
            requests: 1,
            tokens: TokenCount(output: 1_000_000)
        )
        let reported = try DailyUsage(
            day: #require(DayKey("2026-09-01")),
            providerID: "p",
            model: "claude-opus-5",
            requests: 1,
            tokens: TokenCount(output: 1_000_000),
            reportedCost: 1.5
        )
        let unknown = try DailyUsage(
            day: #require(DayKey("2026-09-01")),
            providerID: "p",
            model: nil,
            requests: 1,
            tokens: TokenCount(output: 1)
        )

        #expect(ModelPrices.cost(of: priced) == 25)
        #expect(ModelPrices.cost(of: reported) == 1.5)
        #expect(ModelPrices.cost(of: unknown) == nil)
    }
}
