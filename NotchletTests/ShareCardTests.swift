import AppKit
import Foundation
@testable import Notchlet
import Testing

struct ShareCardTests {
    private static let claude = ShareCard.Provider(id: "claude-code", name: "Claude Code", logoAssetName: "ClaudeLogo")
    private static let codex = ShareCard.Provider(id: "codex", name: "Codex", logoAssetName: "OpenAILogo")

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private let today = TestSupport.day("2026-09-03")

    private static func row(_ day: String, model: String? = "claude-opus-5", output: Int) -> DailyUsage {
        DailyUsage(
            day: TestSupport.day(day),
            providerID: "claude-code",
            model: model,
            requests: 3,
            tokens: TokenCount(input: 1000, output: output)
        )
    }

    /// Four active days in the last week, one gap, one model unpriced.
    private let ledger = UsageLedger(rows: [
        Self.row("2026-08-28", output: 1_000_000),
        Self.row("2026-08-29", output: 1_000_000),
        Self.row("2026-08-31", output: 2_000_000),
        Self.row("2026-09-01", output: 500_000),
        Self.row("2026-09-01", model: "codex-auto-review", output: 10),
        Self.row("2026-09-03", model: "claude-sonnet-5", output: 500_000),
    ])

    private func make(_ options: ShareOptions, providers: [ShareCard.Provider] = [claude],
                      coverageStart: DayKey? = nil) -> ShareCard
    {
        ShareCard.make(
            options: options, providers: providers, ledger: ledger,
            coverageStart: coverageStart, today: today, calendar: calendar
        )
    }

    @Test func costHeadlineWithItsStats() {
        let card = make(ShareOptions(period: .week))
        #expect(card.headline == .cost("$120.02"))
        #expect(card.caption == "Claude Code usage at API list prices")
        #expect(card.period == "Last 7 days · Aug 28 to Sep 3, 2026")
        #expect(card.stats.map(\.value) == ["5M", "18", "5 of 7", "2 days"])
        #expect(card.stats.map(\.label) == ["tokens", "requests", "days active", "longest streak"])
        #expect(card.activity != nil)
        #expect(card.spend == nil)
        #expect(card.models.map(\.name) == ["claude-opus-5", "claude-sonnet-5", "codex-auto-review"])
        #expect(card.models[0].share > 0.8)
        #expect(card.footer == "codex-auto-review not priced")
    }

    @Test func tokensTakeTheHeadlineWhenCostIsOff() {
        var options = ShareOptions(period: .month)
        options.showsCost = false
        let card = make(options, providers: [Self.claude, Self.codex])
        #expect(card.headline == .tokens("5M"))
        #expect(card.caption == "tokens with Claude Code and Codex in 30 days")
        #expect(card.stats.map(\.label) == ["requests", "days active", "longest streak", "models"])
        #expect(card.stats.last?.value == "3")
        // Unpriced models are only a caveat when a cost is shown.
        #expect(card.footer == ShareCard.tagline)
    }

    @Test func todayHasNoDayStats() {
        let card = make(ShareOptions(period: .today))
        #expect(card.period == "Today · Sep 3, 2026")
        #expect(card.stats.map(\.label) == ["tokens", "requests", "model"])
        #expect(card.headline == .cost("$7.50"))
    }

    @Test func nothingInThePeriodMeansNoHeadline() {
        let empty = UsageLedger(rows: [])
        let card = ShareCard.make(
            options: ShareOptions(), providers: [Self.claude], ledger: empty,
            coverageStart: nil, today: today, calendar: calendar
        )
        #expect(card.headline == .none)
        #expect(card.hasUsage == false)
        #expect(card.caption == "No Claude Code usage in 30 days")
        #expect(card.stats.isEmpty)
        #expect(card.models.isEmpty)
        #expect(card.hasGraph == false)
    }

    @Test func coverageInsideThePeriodMovesToTheHeader() {
        let card = make(ShareOptions(period: .year), coverageStart: TestSupport.day("2025-12-08"))
        #expect(card.period == "12 months · since Dec 8, 2025")
        #expect(card.footer == "codex-auto-review not priced")
        #expect(card.stats[2].value == "5")
    }

    @Test func coverageOlderThanThePeriodStaysInTheFooter() {
        var options = ShareOptions(period: .week)
        options.showsCost = false
        let card = make(options, coverageStart: TestSupport.day("2026-05-01"))
        #expect(card.period == "Last 7 days · Aug 28 to Sep 3, 2026")
        #expect(card.footer == "History since May 1")
    }

    @Test func modelRowsGrowWithoutAGraph() {
        var options = ShareOptions(period: .month)
        options.graph = .none
        let card = make(options)
        #expect(card.hasGraph == false)
        #expect(ShareCard.modelRowCount(graph: .none) == 5)
        #expect(card.models.count == 3)
        options.showsModels = false
        #expect(make(options).models.isEmpty)
    }

    @Test func spendGraphCarriesThirtyDays() {
        var options = ShareOptions(period: .month)
        options.graph = .spend
        let card = make(options)
        #expect(card.spend?.points.count == SpendSeries.days)
        #expect(card.activity == nil)
    }

    @Test func providersPhrase() {
        #expect(ShareCard.providersPhrase([Self.claude]) == "Claude Code")
        #expect(ShareCard.providersPhrase([Self.claude, Self.codex]) == "Claude Code and Codex")
        #expect(ShareCard.providersPhrase([Self.claude, Self.codex, Self.claude]) == "agent")
    }

    /// The whole ImageRenderer contract: the PNG has the right pixel size
    /// and is not one flat color, which is what a material sneaking into
    /// the view would produce.
    @MainActor
    @Test func rendersAFullCardAtTwoX() throws {
        let card = make(ShareOptions(period: .month), providers: [Self.claude, Self.codex])
        let png = try #require(ShareRenderer.png(card: card, theme: .notch, calendar: calendar))
        let bitmap = try #require(NSBitmapImageRep(data: png))
        #expect(bitmap.pixelsWide == 2400)
        #expect(bitmap.pixelsHigh == 1350)
        let corner = try #require(bitmap.colorAt(x: 10, y: 10))
        let middle = try #require(bitmap.colorAt(x: 1200, y: 700))
        #expect(corner != middle)
        try png.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "notchlet-share-test.png"))
    }
}
