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
        let price = try #require(ModelPrices.price(for: "gpt-5.5"))
        #expect(price.cacheWrite5m == price.input)
        #expect(price.cost(of: TokenCount(input: 2_000_000, cacheRead: 1_000_000, output: 100_000)) == 13.5)
    }

    @Test(arguments: ["gpt-6-astra", "openai/GPT-6-Astra", "gpt-6-astra-2026-09-01"])
    func astraIncludesCacheWritePricing(model: String) throws {
        let price = try #require(ModelPrices.price(for: model))
        #expect(price == ModelPrice(input: 10, output: 50, cacheRead: 1, cacheWrite5m: 12.5, cacheWrite1h: 12.5))
        #expect(price.cost(of: TokenCount(input: 1_000_000, cacheRead: 2_000_000,
                                          cacheWrite5m: 1_000_000, output: 100_000)) == 29.5)
    }

    @Test(arguments: ["gpt-6-sol", "openai/GPT-6-Sol", "gpt-6-sol-2026-09-22"])
    func solIncludesCacheWritePricing(model: String) throws {
        let price = try #require(ModelPrices.price(for: model))
        #expect(price == ModelPrice(input: 2, output: 10, cacheRead: 0.2, cacheWrite5m: 2.5, cacheWrite1h: 2.5))
    }

    @Test(arguments: ["gpt-6-luna", "openai/GPT-6-Luna", "gpt-6-luna-2026-09-22"])
    func lunaIncludesCacheWritePricing(model: String) throws {
        let price = try #require(ModelPrices.price(for: model))
        #expect(price == ModelPrice(input: 0.1, output: 0.5, cacheRead: 0.01, cacheWrite5m: 0.125, cacheWrite1h: 0.125))
    }

    @Test(arguments: ["gpt-6.1-sol", "openai/GPT-6.1-Sol", "gpt-6.1-sol-2026-10-01"])
    func sol61HasItsOwnCacheDiscount(model: String) throws {
        let price = try #require(ModelPrices.price(for: model))
        #expect(price == ModelPrice(input: 2, output: 10, cacheRead: 0.1, cacheWrite5m: 2.5, cacheWrite1h: 2.5))
        #expect(price.cost(of: TokenCount(input: 1_000_000, cacheRead: 2_000_000,
                                          cacheWrite5m: 1_000_000, output: 100_000)) == 5.7)
        #expect(ModelPrices.price(for: "gpt-6-sol")?.cacheRead == 0.2)
    }

    @Test(arguments: ["claude-sonnet-5-5", "anthropic/claude-sonnet-5-5[1m]", "claude-sonnet-5-5-20260928"])
    func sonnet55IncludesBothCacheDurations(model: String) throws {
        let price = try #require(ModelPrices.price(for: model))
        #expect(price == ModelPrice(input: 2, output: 10, cacheRead: 0.2, cacheWrite5m: 2.5, cacheWrite1h: 4))
    }

    @Test(arguments: [
        ("gpt-5.6-sol-fast", 8.0, 40.0, 0.8, 10.0, 10.0),
        ("gpt-5.6-terra-fast", 4.0, 24.0, 0.4, 5.0, 5.0),
        ("gpt-5.6-luna-fast", 0.4, 2.4, 0.04, 0.5, 0.5),
        ("gpt-6-astra-fast", 20.0, 100.0, 2.0, 25.0, 25.0),
        ("gpt-6-sol-fast", 4.0, 20.0, 0.4, 5.0, 5.0),
        ("gpt-6.1-sol-fast", 4.0, 20.0, 0.2, 5.0, 5.0),
        ("gpt-6-luna-fast", 0.2, 1.0, 0.02, 0.25, 0.25),
        ("claude-opus-5-5-fast", 8.0, 40.0, 0.4, 10.0, 16.0),
        ("gemini-3.5-flash", 1.5, 9.0, 0.15, 1.5, 1.5),
        ("gemini-3.6-flash", 0.75, 3.75, 0.075, 0.75, 0.75),
        ("gemini-3.7-flash", 0.75, 3.75, 0.075, 0.75, 0.75),
        ("google/gemini-3.8-flash", 0.75, 3.75, 0.075, 0.75, 0.75),
        ("gemini-3.5-flash-lite", 0.3, 2.5, 0.03, 0.3, 0.3),
        ("gemini-3.1-flash-lite", 0.25, 1.5, 0.025, 0.25, 0.25),
    ])
    func recentVendorRates(
        model: String,
        input: Double,
        output: Double,
        read: Double,
        write5m: Double,
        write1h: Double
    ) throws {
        let price = try #require(ModelPrices.price(for: model))
        #expect(price == ModelPrice(
            input: input,
            output: output,
            cacheRead: read,
            cacheWrite5m: write5m,
            cacheWrite1h: write1h
        ))
    }

    @Test(arguments: [
        ("Grok 4.5", 2.0, 6.0, 0.5),
        ("Grok 4.5 (Fast)", 4.0, 18.0, 1.0),
        ("Grok 4.6", 2.0, 6.0, 0.5),
        ("Grok 4.6 (Fast)", 4.0, 12.0, 1.0),
        ("grok-4.7-high", 2.0, 6.0, 0.5),
        ("grok-4.7-xhigh-fast", 4.0, 12.0, 1.0),
        ("Grok 4.7 500k", 4.0, 12.0, 1.0),
        ("Grok 4.7 500k (Fast)", 6.0, 18.0, 1.5),
        ("Gemini 2.5 Flash", 0.3, 2.5, 0.03),
        ("Gemini 3 Flash", 0.5, 3.0, 0.05),
        ("Gemini 3 Pro", 2.0, 12.0, 0.2),
        ("Gemini 3.1 Pro", 2.0, 12.0, 0.2),
        ("Gemini 3.6 Flash", 1.5, 7.5, 0.15),
        ("Gemini 3.7 Flash", 0.75, 3.5, 0.075),
        ("gemini-3.8-flash-high", 0.75, 3.5, 0.075),
        ("GLM 5.2", 1.4, 4.4, 0.26),
        ("GLM 5.3", 1.4, 4.4, 0.26),
        ("GLM 5.3 Flash", 0.15, 0.5, 0.029),
        ("Kimi K2.7 Code", 0.95, 4.0, 0.19),
        ("Kimi K3", 3.0, 15.0, 0.3),
        ("muse-spark-1.3-minimal", 1.25, 4.25, 0.15),
        ("Muse Spark 1.3 Extra High", 1.25, 4.25, 0.15),
    ])
    func cursorRatesMatchItsPublishedTable(label: String, input: Double, output: Double, read: Double) throws {
        let model = CursorModelNames.canonical(label)
        let price = try #require(ModelPrices.price(for: model, providerID: "cursor"))
        #expect(price == ModelPrice(
            input: input,
            output: output,
            cacheRead: read,
            cacheWrite5m: input,
            cacheWrite1h: input
        ))
    }

    @Test func cursorPricesDoNotLeakIntoOtherProviders() throws {
        let day = try #require(DayKey("2026-10-07"))
        let cursor = DailyUsage(day: day, providerID: "cursor", model: "gemini-3.8-flash",
                                requests: 1, tokens: TokenCount(output: 1_000_000))
        let openCode = DailyUsage(day: day, providerID: "opencode", model: "google/gemini-3.8-flash",
                                  requests: 1, tokens: TokenCount(output: 1_000_000))
        var reported = cursor
        reported.reportedCost = 1.25

        #expect(ModelPrices.cost(of: cursor) == 3.5)
        #expect(ModelPrices.cost(of: openCode) == 3.75)
        #expect(ModelPrices.cost(of: reported) == 1.25)
        #expect(ModelPrices.price(for: "muse-spark-1.3", providerID: "opencode") == nil)
    }

    @Test(arguments: ["claude-opus-5-5", "anthropic/claude-opus-5-5[1m]", "claude-opus-5-5-20260922"])
    func opus55HasDiscountedCacheReads(model: String) throws {
        let price = try #require(ModelPrices.price(for: model))
        #expect(price == ModelPrice(input: 4, output: 20, cacheRead: 0.2, cacheWrite5m: 5, cacheWrite1h: 8))
    }

    @Test(arguments: ["claude-fable-5-1", "anthropic/claude-fable-5-1[1m]", "claude-mythos-5-1"])
    func latestAnthropicModelsHaveDiscountedCacheReads(model: String) throws {
        let price = try #require(ModelPrices.price(for: model))
        #expect(price == ModelPrice(input: 10, output: 50, cacheRead: 0.25, cacheWrite5m: 12.5, cacheWrite1h: 20))
        #expect(price.cost(of: TokenCount(input: 1_000_000, cacheRead: 2_000_000,
                                          cacheWrite5m: 1_000_000, cacheWrite1h: 1_000_000,
                                          output: 100_000)) == 48)
        #expect(ModelPrices.price(for: "claude-fable-5")?.cacheRead == 1)
        #expect(ModelPrices.price(for: "claude-mythos-5")?.cacheRead == 1)
    }

    @Test func currentSolAndSonnetRates() throws {
        let sol = try #require(ModelPrices.price(for: "gpt-5.6-sol"))
        #expect(sol == ModelPrice(input: 4, output: 20, cacheRead: 0.4, cacheWrite5m: 5, cacheWrite1h: 5))
        let sonnet = try #require(ModelPrices.price(for: "claude-sonnet-5"))
        #expect(sonnet == ModelPrice(input: 2, output: 10, cacheRead: 0.2, cacheWrite5m: 2.5, cacheWrite1h: 4))
    }

    @Test func unknownModelsStayUnpriced() {
        #expect(ModelPrices.price(for: "codex-auto-review") == nil)
        #expect(ModelPrices.price(for: "gpt-5.7-mini") == nil)
        #expect(ModelPrices.price(for: "gpt-6.1-mini") == nil)
        #expect(ModelPrices.price(for: "claude-haiku-5-5") == nil)
        #expect(ModelPrices.price(for: "grok-4.8", providerID: "cursor") == nil)
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
