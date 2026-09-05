import Foundation

/// The five buckets every vendor bills. `input` is the uncached part of the
/// prompt (Codex counts cached tokens inside its input and its parser
/// subtracts them); reasoning tokens are output; Anthropic bills the two
/// cache-write tiers differently, so they stay apart.
nonisolated struct TokenCount: Hashable, Codable, Sendable {
    var input = 0
    var cacheRead = 0
    var cacheWrite5m = 0
    var cacheWrite1h = 0
    var output = 0

    static let zero = TokenCount()

    /// What the pane calls input.
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

/// One request as a source recorded it.
nonisolated struct UsageEvent: Hashable, Sendable {
    /// For sources that record one request more than once (Claude writes a
    /// line per content block, each with the full usage). Nil otherwise.
    var id: String?
    var model: String?
    var timestamp: Date
    var tokens: TokenCount
    /// In dollars, as the CLI computed it. Wins over the price table.
    var reportedCost: Double?
}

/// A Gregorian calendar day in the user's time zone, "2026-09-03". The only
/// place a `Date` becomes a day. Always Gregorian, whatever calendar the
/// Mac is set to: the archive stores these and parses them back.
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

    /// "yyyy-MM-dd". A day the month does not have is refused; `Calendar`
    /// would roll it into the next month.
    init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1 ... 12).contains(month), (1 ... Self.days(inMonth: month, year: year)).contains(day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

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

    func start(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    func advanced(by days: Int, calendar: Calendar) -> DayKey {
        let date = calendar.date(byAdding: .day, value: days, to: start(in: calendar)) ?? start(in: calendar)
        return DayKey(date, calendar: calendar)
    }

    /// Up to and including `other`.
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

nonisolated extension Calendar {
    /// The calendar every `DayKey` is made with; a Mac set to another
    /// calendar would produce keys the archive cannot read back.
    static var localGregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Calendar.current.timeZone
        calendar.locale = Calendar.current.locale
        return calendar
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

/// One provider's use of one model on one day: what the archive keeps and
/// the pane sums.
nonisolated struct DailyUsage: Hashable, Codable, Sendable {
    var day: DayKey
    var providerID: String
    var model: String?
    var requests: Int
    var tokens: TokenCount
    var reportedCost: Double?
}

nonisolated enum UsageRollup {
    /// Keeps the fullest recording of each id; events without one are kept
    /// as they are.
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

    /// Events the CLI priced and events it did not stay in separate rows,
    /// so a reported cost never stands in for tokens it did not cover.
    /// Sorted so the archive on disk stays stable.
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
