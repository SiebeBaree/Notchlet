import Foundation

/// The graph on a shared image: the pane's two graphs are alternatives
/// here as well, both at once would crowd the card.
nonisolated enum ShareGraph: String, CaseIterable, Sendable {
    case activity
    case spend
    case none
}

nonisolated enum ShareThemeID: String, CaseIterable, Sendable {
    case notch
    case midnight
    case paper
}

/// What the editor lets the user choose. The headline is always on the
/// card; `showsCost` decides whether it is dollars or tokens.
nonisolated struct ShareOptions: Equatable, Sendable {
    var period: UsageHistory.Range = .month
    var showsCost = true
    var graph: ShareGraph = .activity
    var showsModels = true
    var theme: ShareThemeID = .notch
}

/// Everything drawn on a shared image, already formatted. Built once from
/// the ledger by `make`, so the view never touches history and the
/// wording can be tested without rendering anything.
nonisolated struct ShareCard: Equatable, Sendable {
    struct Provider: Equatable, Sendable {
        let id: String
        let name: String
        let logoAssetName: String
    }

    enum Headline: Equatable, Sendable {
        case cost(String)
        case tokens(String)
        /// Nothing in the period. The editor disables export.
        case none
    }

    struct Stat: Equatable, Sendable {
        let value: String
        let label: String
    }

    struct ModelRow: Equatable, Identifiable, Sendable {
        let id: String
        let name: String
        let tokens: String
        /// This model's part of the period's tokens, for the bar.
        let share: Double
    }

    static let tagline = "Your agent limits, in the notch."

    var providers: [Provider]
    /// "Last 30 days · Aug 5 to Sep 3, 2026", right of the header.
    var period: String
    var headline: Headline
    var caption: String
    var stats: [Stat]
    var activity: ActivityGrid?
    var spend: SpendSeries?
    var models: [ModelRow]
    /// The caveats the pane's footer would show, or the tagline.
    var footer: String

    var hasUsage: Bool { headline != .none }
    var hasGraph: Bool { activity != nil || spend != nil }

    /// How many model rows fit: three next to a graph, five without one.
    static func modelRowCount(graph: ShareGraph) -> Int {
        graph == .none ? 5 : 3
    }

    static func make(
        options: ShareOptions,
        providers: [Provider],
        ledger: UsageLedger,
        coverageStart: DayKey?,
        today: DayKey,
        calendar: Calendar
    ) -> ShareCard {
        let span = options.period.span(endingOn: today, calendar: calendar)
        let summary = ledger.summary(span)
        let models = ledger.models(span)
        let who = providersPhrase(providers)
        let when = periodPhrase(options.period)

        let headline: Headline
        let caption: String
        var stats: [Stat] = []
        if summary.tokens == 0 {
            headline = .none
            caption = "No \(who) usage \(when)"
        } else if options.showsCost, let cost = summary.cost {
            headline = .cost(HistoryCopy.cost(cost))
            caption = "\(who.prefix(1).uppercased() + who.dropFirst()) usage at API list prices"
            stats.append(Stat(value: HistoryCopy.tokens(summary.tokens), label: "tokens"))
            stats.append(Stat(value: count(summary.requests), label: "requests"))
            if options.period == .today {
                stats.append(Stat(value: count(models.count), label: models.count == 1 ? "model" : "models"))
            } else {
                stats += dayStats(ledger: ledger, span: span, period: options.period, calendar: calendar)
            }
        } else {
            headline = .tokens(HistoryCopy.tokens(summary.tokens))
            caption = "tokens with \(who) \(when)"
            stats.append(Stat(value: count(summary.requests), label: "requests"))
            if options.period != .today {
                stats += dayStats(ledger: ledger, span: span, period: options.period, calendar: calendar)
            }
            stats.append(Stat(value: count(models.count), label: models.count == 1 ? "model" : "models"))
        }

        // A card with nothing in its period shows nothing but that.
        var activity: ActivityGrid?
        var spend: SpendSeries?
        var graphStart: DayKey?
        switch summary.tokens == 0 ? .none : options.graph {
        case .activity:
            let gridSpan = today.advanced(by: -(ActivityGrid.weeks * 7), calendar: calendar) ... today
            let grid = ActivityGrid(
                today: today, calendar: calendar,
                tokens: ledger.byDay(gridSpan).mapValues(\.summary.tokens),
                coverageStart: coverageStart
            )
            activity = grid
            graphStart = grid.start
        case .spend:
            let start = today.advanced(by: 1 - SpendSeries.days, calendar: calendar)
            spend = SpendSeries(
                today: today, calendar: calendar,
                costs: ledger.byDay(start ... today).compactMapValues(\.summary.cost),
                coverageStart: coverageStart
            )
            graphStart = start
        case .none:
            break
        }

        let rows: [ModelRow] = options.showsModels && summary.tokens > 0
            ? models.prefix(modelRowCount(graph: options.graph)).map { model in
                ModelRow(
                    id: model.id,
                    name: model.model.map(ModelPrices.normalize) ?? "unknown model",
                    tokens: HistoryCopy.tokens(model.tokens.total),
                    share: summary.tokens > 0 ? Double(model.tokens.total) / Double(summary.tokens) : 0
                )
            }
            : []

        // Coverage inside the period is said in the header; the footer only
        // repeats it when the graph reaches further back than that.
        let coverageInPeriod = coverageStart.map { $0 > span.lowerBound } ?? false
        var caveats = HistoryCopy.caveats(
            unpricedModels: headline.isCost ? summary.unpricedModels : [],
            coverageStart: coverageInPeriod ? nil : coverageStart,
            graphStart: graphStart ?? span.lowerBound,
            calendar: calendar
        )
        if caveats.isEmpty {
            caveats = [tagline]
        }

        return ShareCard(
            providers: providers,
            period: periodLabel(options.period, span: span, coverageStart: coverageStart, calendar: calendar),
            headline: headline,
            caption: caption,
            stats: stats,
            activity: activity,
            spend: spend,
            models: rows,
            footer: caveats.joined(separator: " · ")
        )
    }

    /// "Today · Sep 3, 2026", "Last 30 days · Aug 5 to Sep 3, 2026",
    /// "12 months · Sep 2025 to Sep 2026", or "since" the archive's first
    /// day when that falls inside the period.
    static func periodLabel(
        _ period: UsageHistory.Range,
        span: ClosedRange<DayKey>,
        coverageStart: DayKey?,
        calendar: Calendar
    ) -> String {
        let name = switch period {
        case .today: "Today"
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        case .year: "12 months"
        }
        let dates = if let coverageStart, coverageStart > span.lowerBound {
            "since \(HistoryCopy.fullDay(coverageStart, calendar: calendar))"
        } else {
            switch period {
            case .today:
                HistoryCopy.fullDay(span.upperBound, calendar: calendar)
            case .week, .month:
                "\(HistoryCopy.shortDay(span.lowerBound, calendar: calendar)) to "
                    + HistoryCopy.fullDay(span.upperBound, calendar: calendar)
            case .year:
                "\(HistoryCopy.monthYear(span.lowerBound, calendar: calendar)) to "
                    + HistoryCopy.monthYear(span.upperBound, calendar: calendar)
            }
        }
        return "\(name) · \(dates)"
    }

    /// One provider by name, two joined with "and", more as "agent".
    static func providersPhrase(_ providers: [Provider]) -> String {
        switch providers.count {
        case 1: providers[0].name
        case 2: "\(providers[0].name) and \(providers[1].name)"
        default: "agent"
        }
    }

    private static func periodPhrase(_ period: UsageHistory.Range) -> String {
        switch period {
        case .today: "today"
        case .week: "in 7 days"
        case .month: "in 30 days"
        case .year: "in 12 months"
        }
    }

    /// Days active as "27 of 30" over a fixed span, a plain count over a
    /// year, then the longest streak.
    private static func dayStats(
        ledger: UsageLedger,
        span: ClosedRange<DayKey>,
        period: UsageHistory.Range,
        calendar: Calendar
    ) -> [Stat] {
        let active = ledger.activeDays(span)
        let streak = ledger.longestStreak(span, calendar: calendar)
        return [
            Stat(value: period == .year ? count(active) : "\(active) of \(period.days)", label: "days active"),
            Stat(value: streak == 1 ? "1 day" : "\(streak) days", label: "longest streak"),
        ]
    }

    /// "3,418", pinned to en_US like the rest of the history copy.
    private static func count(_ value: Int) -> String {
        value.formatted(.number.locale(Locale(identifier: "en_US")))
    }
}

nonisolated extension ShareCard.Headline {
    var isCost: Bool {
        if case .cost = self {
            return true
        }
        return false
    }
}
