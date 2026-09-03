import Foundation

/// The five token buckets every vendor bills. Reasoning and thinking tokens
/// are output. `input` is always the uncached part of the prompt: Codex
/// reports cached tokens inside its input count and its parser subtracts
/// them, Claude reports them apart. Anthropic bills the two cache-write
/// tiers differently, so they stay apart too.
nonisolated struct TokenCount: Hashable, Codable, Sendable {
    var input = 0
    var cacheRead = 0
    var cacheWrite5m = 0
    var cacheWrite1h = 0
    var output = 0

    static let zero = TokenCount()

    /// Everything that went in, cached or not: what the pane calls input.
    var promptTokens: Int { input + cacheRead + cacheWrite5m + cacheWrite1h }
    var total: Int { promptTokens + output }

    static func + (lhs: TokenCount, rhs: TokenCount) -> TokenCount {
        TokenCount(
            input: lhs.input + rhs.input,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite5m: lhs.cacheWrite5m + rhs.cacheWrite5m,
            cacheWrite1h: lhs.cacheWrite1h + rhs.cacheWrite1h,
            output: lhs.output + rhs.output
        )
    }

    static func += (lhs: inout TokenCount, rhs: TokenCount) {
        lhs = lhs + rhs
    }
}

/// One request as a source recorded it. Provider-neutral so the rollup, the
/// pricing and the pane never branch on where it came from.
nonisolated struct UsageEvent: Hashable, Sendable {
    /// Identity for sources that can record one request more than once
    /// (Claude writes a line per content block, each with the full usage).
    /// Nil for sources that never repeat.
    var id: String?
    /// Nil when the source did not say. Shown as unknown, never priced.
    var model: String?
    var timestamp: Date
    var tokens: TokenCount
    /// A cost the CLI computed itself (OpenCode, older Claude Code logs).
    /// Wins over the price table, in dollars.
    var reportedCost: Double?
}

/// A calendar day in the user's own time zone, "2026-09-03". The only place
/// a `Date` becomes a day, so every rollup buckets the same way.
nonisolated struct DayKey: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Parses "yyyy-MM-dd", the form the archive stores. A day the month
    /// does not have is refused: `Calendar` would roll it into the next
    /// month and the key would no longer name its own day.
    init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1 ... 12).contains(month), (1 ... Self.days(inMonth: month, year: year)).contains(day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// Gregorian month lengths, leap years included.
    static func days(inMonth month: Int, year: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    var string: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Midnight at the start of the day.
    func start(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    func advanced(by days: Int, calendar: Calendar) -> DayKey {
        let date = calendar.date(byAdding: .day, value: days, to: start(in: calendar)) ?? start(in: calendar)
        return DayKey(date, calendar: calendar)
    }

    /// Days from this day up to and including `other`, in order.
    func days(through other: DayKey, calendar: Calendar) -> [DayKey] {
        var days: [DayKey] = []
        var current = self
        while current <= other {
            days.append(current)
            current = current.advanced(by: 1, calendar: calendar)
        }
        return days
    }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension DayKey: Codable {
    init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let day = DayKey(string) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Not a day: \(string)"
            ))
        }
        self = day
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}

/// One provider's use of one model on one day, priced by the CLI or not.
/// The unit the archive keeps and the pane sums, so a per-day, per-model
/// breakdown is always there.
nonisolated struct DailyUsage: Hashable, Codable, Sendable {
    var day: DayKey
    var providerID: String
    var model: String?
    var requests: Int
    var tokens: TokenCount
    /// Sum of the costs the CLI reported, when it reports any.
    var reportedCost: Double?
}

/// Turns events into daily rows.
nonisolated enum UsageRollup {
    /// Drops repeated recordings of one request, keeping the fullest. Events
    /// without an id are kept as they are.
    static func deduplicated(_ events: [UsageEvent]) -> [UsageEvent] {
        var keyed: [String: UsageEvent] = [:]
        var unkeyed: [UsageEvent] = []
        for event in events {
            guard let id = event.id else {
                unkeyed.append(event)
                continue
            }
            if let existing = keyed[id], existing.tokens.total >= event.tokens.total {
                continue
            }
            keyed[id] = event
        }
        return unkeyed + keyed.values
    }

    /// Buckets by local day and model. Events the CLI priced itself and
    /// events it did not stay in separate rows, so a reported cost never
    /// stands in for tokens it did not cover and the price table gets the
    /// rest. Sorted by day then model so the archive on disk stays stable.
    static func daily(_ events: [UsageEvent], providerID: String, calendar: Calendar) -> [DailyUsage] {
        struct Key: Hashable {
            let day: DayKey
            let model: String?
            let hasReportedCost: Bool
        }

        var rows: [Key: DailyUsage] = [:]
        for event in events {
            let key = Key(
                day: DayKey(event.timestamp, calendar: calendar),
                model: event.model,
                hasReportedCost: event.reportedCost != nil
            )
            var row = rows[key] ?? DailyUsage(
                day: key.day, providerID: providerID, model: key.model, requests: 0, tokens: .zero
            )
            row.requests += 1
            row.tokens += event.tokens
            if let cost = event.reportedCost {
                row.reportedCost = (row.reportedCost ?? 0) + cost
            }
            rows[key] = row
        }
        return rows.values.sorted {
            ($0.day, $0.model ?? "", $0.reportedCost == nil ? 0 : 1) < (
                $1.day,
                $1.model ?? "",
                $1.reportedCost == nil ? 0 : 1
            )
        }
    }
}
