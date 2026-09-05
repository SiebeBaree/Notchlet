import Foundation
import Observation

/// The rows of one or more providers and the sums the pane asks for. Pure
/// so the arithmetic stays testable with hand-written rows.
nonisolated struct UsageLedger: Sendable {
    /// Cost and tokens over a span of days. `cost` is nil when nothing in
    /// the span could be priced; `unpricedModels` names what was left out
    /// of it, so a low number never passes for a complete one.
    struct Summary: Equatable, Sendable {
        var requests = 0
        var tokens = 0
        var cost: Double?
        var unpricedModels: [String] = []
    }

    /// One model's share, across providers or within one.
    struct ModelUsage: Identifiable, Equatable, Sendable {
        let providerID: String
        let model: String?
        var requests: Int
        var tokens: TokenCount
        var cost: Double?

        var id: String { "\(providerID)/\(model ?? "")" }
    }

    /// One day, with its models for the graph's hover detail.
    struct DayUsage: Equatable, Sendable {
        let day: DayKey
        var summary: Summary
        var models: [ModelUsage]
    }

    var rows: [DailyUsage]

    func summary(_ days: ClosedRange<DayKey>) -> Summary {
        Self.summarize(rows.filter { days.contains($0.day) })
    }

    /// Models by total tokens, largest first.
    func models(_ days: ClosedRange<DayKey>) -> [ModelUsage] {
        Self.models(of: rows.filter { days.contains($0.day) })
    }

    /// Days in the span with any tokens.
    func activeDays(_ days: ClosedRange<DayKey>) -> Int {
        Set(rows.filter { days.contains($0.day) && $0.tokens.total > 0 }.map(\.day)).count
    }

    /// The most consecutive active days inside the span.
    func longestStreak(_ days: ClosedRange<DayKey>, calendar: Calendar) -> Int {
        let active = Set(rows.filter { days.contains($0.day) && $0.tokens.total > 0 }.map(\.day))
        var longest = 0
        var current = 0
        var day = days.lowerBound
        while day <= days.upperBound {
            current = active.contains(day) ? current + 1 : 0
            longest = max(longest, current)
            day = day.advanced(by: 1, calendar: calendar)
        }
        return longest
    }

    /// Every day in the span that has rows.
    func byDay(_ days: ClosedRange<DayKey>) -> [DayKey: DayUsage] {
        let grouped = Dictionary(grouping: rows.filter { days.contains($0.day) }, by: \.day)
        return grouped.mapValues { rows in
            DayUsage(day: rows[0].day, summary: Self.summarize(rows), models: Self.models(of: rows))
        }
    }

    private static func summarize(_ rows: [DailyUsage]) -> Summary {
        var summary = Summary()
        var unpriced: Set<String> = []
        for row in rows {
            summary.requests += row.requests
            summary.tokens += row.tokens.total
            if let cost = ModelPrices.cost(of: row) {
                summary.cost = (summary.cost ?? 0) + cost
            } else {
                unpriced.insert(row.model ?? "unknown model")
            }
        }
        summary.unpricedModels = unpriced.sorted()
        return summary
    }

    private static func models(of rows: [DailyUsage]) -> [ModelUsage] {
        struct Key: Hashable {
            let providerID: String
            let model: String?
        }

        var models: [Key: ModelUsage] = [:]
        for row in rows {
            let key = Key(providerID: row.providerID, model: row.model)
            var usage = models[key] ?? ModelUsage(
                providerID: key.providerID,
                model: key.model,
                requests: 0,
                tokens: .zero
            )
            usage.requests += row.requests
            usage.tokens += row.tokens
            if let cost = ModelPrices.cost(of: row) {
                usage.cost = (usage.cost ?? 0) + cost
            }
            models[key] = usage
        }
        return models.values.sorted { ($0.tokens.total, $0.id) > ($1.tokens.total, $1.id) }
    }
}

/// Past usage for the providers that have a source, and the ingest cadence
/// that keeps it current: once shortly after launch, once an hour after
/// that so days seal on time, and whenever the pane opens onto data older
/// than a minute. Sources are read one at a time; a first read of a year of
/// logs is heavy enough without two of them racing.
@Observable
final class UsageHistory {
    enum Scope: Hashable, Sendable {
        case all
        case provider(String)

        /// "all" or the provider id, as UserDefaults keeps it.
        var storedValue: String {
            switch self {
            case .all: "all"
            case let .provider(id): id
            }
        }

        init(storedValue: String) {
            self = storedValue == "all" ? .all : .provider(storedValue)
        }
    }

    /// The spans the pane's tiles and the share card sum over. The pane
    /// shows the first three; the year exists for the card.
    nonisolated enum Range: String, CaseIterable, Sendable {
        case today
        case week
        case month
        case year

        var days: Int {
            switch self {
            case .today: 1
            case .week: 7
            case .month: 30
            case .year: 365
            }
        }

        func span(endingOn today: DayKey, calendar: Calendar) -> ClosedRange<DayKey> {
            today.advanced(by: 1 - days, calendar: calendar) ... today
        }
    }

    static let ingestInterval: TimeInterval = 3600
    /// Data older than this is refreshed when the pane opens onto it.
    static let staleAge: TimeInterval = 60
    /// Live providers fetch first at launch; the logs can wait this long.
    static let launchDelay: TimeInterval = 5

    let calendar: Calendar
    private let store: UsageStore
    private let ingestor: HistoryIngestor
    private(set) var histories: [String: ProviderHistory] = [:]
    private(set) var lastIngestAt: Date?
    private(set) var isIngesting = false
    /// Providers whose last ingest threw, so the pane can say so.
    private(set) var failedProviderIDs: Set<String> = []
    private var loop: Task<Void, Never>?

    init(store: UsageStore, archives: HistoryArchiveStore = .default, calendar: Calendar = .localGregorian) {
        self.store = store
        self.calendar = calendar
        ingestor = HistoryIngestor(archives: archives, calendar: calendar)
    }

    /// Providers that are on and have somewhere to read history from.
    var providersWithHistory: [any UsageProvider] {
        store.entries.map(\.provider).filter { store.isEnabled($0.id) && $0.history != nil }
    }

    /// Shows the archives right away and starts the ingest loop.
    func start() {
        Task { [weak self] in
            guard let self else { return }
            for provider in providersWithHistory where histories[provider.id] == nil {
                if let archive = await ingestor.archive(for: provider.id) {
                    histories[provider.id] = ProviderHistory(archive: archive, live: [])
                }
            }
        }
        reschedule(after: Self.launchDelay)
    }

    /// What the pane calls on open: fresh data does nothing, stale data
    /// fetches now without disturbing the hourly cadence.
    func ingestIfStale(now: Date = .now) {
        guard let lastIngestAt else {
            return
        }
        if now.timeIntervalSince(lastIngestAt) > Self.staleAge {
            Task { await ingestAll() }
        }
    }

    /// Restarts the loop, fetching right away when the data is old enough:
    /// what a wake from sleep or a change of providers calls.
    func reschedule(after delay: TimeInterval = 0) {
        loop?.cancel()
        loop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            while !Task.isCancelled {
                guard let self else { return }
                if lastIngestAt.map({ Date.now.timeIntervalSince($0) >= Self.staleAge }) ?? true {
                    await ingestAll()
                }
                try? await Task.sleep(for: .seconds(Self.ingestInterval))
            }
        }
    }

    private func ingestAll() async {
        guard !isIngesting else { return }
        isIngesting = true
        defer { isIngesting = false }
        for provider in providersWithHistory {
            guard let source = provider.history else { continue }
            do {
                histories[provider.id] = try await ingestor.ingest(provider.id, from: source)
                failedProviderIDs.remove(provider.id)
            } catch is CancellationError {
                return
            } catch {
                failedProviderIDs.insert(provider.id)
            }
        }
        lastIngestAt = .now
    }

    // MARK: Queries

    var today: DayKey { DayKey(.now, calendar: calendar) }

    private func providerIDs(in scope: Scope) -> [String] {
        switch scope {
        case .all: providersWithHistory.map(\.id)
        case let .provider(id): [id]
        }
    }

    func ledger(_ scope: Scope) -> UsageLedger {
        UsageLedger(rows: providerIDs(in: scope).flatMap { histories[$0]?.rows ?? [] })
    }

    func summary(_ range: Range, scope: Scope) -> UsageLedger.Summary {
        ledger(scope).summary(range.span(endingOn: today, calendar: calendar))
    }

    func models(_ range: Range, scope: Scope) -> [UsageLedger.ModelUsage] {
        ledger(scope).models(range.span(endingOn: today, calendar: calendar))
    }

    func days(_ span: ClosedRange<DayKey>, scope: Scope) -> [DayKey: UsageLedger.DayUsage] {
        ledger(scope).byDay(span)
    }

    /// The first day every provider in the scope can vouch for, so the
    /// latest of their coverage starts: before it the sum is missing a
    /// provider, and a partial day would read as a quiet one. Nil until
    /// every provider has an archive.
    func coverageStart(_ scope: Scope) -> DayKey? {
        let ids = providerIDs(in: scope)
        let starts = ids.compactMap { histories[$0]?.archive.coverageStart }
        return starts.count == ids.count ? starts.max() : nil
    }
}
