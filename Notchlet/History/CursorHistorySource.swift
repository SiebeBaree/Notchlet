import Foundation

/// Cursor's usage as a history source.
///
/// Cursor keeps no log on the Mac; the dashboard's usage export does the
/// job, fetched with the same session cookie the live provider builds. It
/// is a CSV of per-model token aggregates with a date each, account-wide,
/// so this history covers every machine the account is used on. Without
/// an archive yet the first read asks for a year, enough for the graph;
/// after that only the days since the last sealed one.
nonisolated struct CursorHistorySource: UsageHistorySource {
    static let exportURL = URL(string: "https://cursor.com/api/dashboard/export-usage-events-csv")!
    static let firstWindow: TimeInterval = 366 * 24 * 3600

    func events(since: Date?) async throws -> [UsageEvent] {
        let now = Date.now
        var components = URLComponents(url: Self.exportURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(
                name: "startDate",
                value: String(Int((since ?? now.addingTimeInterval(-Self.firstWindow)).timeIntervalSince1970 * 1000))
            ),
            URLQueryItem(name: "endDate", value: String(Int(now.timeIntervalSince1970 * 1000))),
            URLQueryItem(name: "strategy", value: "tokens"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        for (header, value) in try await Self.sessionHeaders() {
            request.setValue(value, forHTTPHeaderField: header)
        }
        request.setValue("text/csv", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.requestFailed }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ProviderError.notAvailable(.rejected)
        }
        guard http.statusCode == 200 else { throw ProviderError.requestFailed }
        return try Self.events(fromCSV: String(decoding: data, as: UTF8.self))
    }

    /// The same sign-in walk the live provider does.
    private static func sessionHeaders() async throws -> [String: String] {
        let provider = await CursorUsageProvider()
        return try await ProviderAuthSettings.selection(for: provider.id, options: provider.authOptions)
            .firstUsable(provider.authOptions, CursorUsageProvider.sessionHeaders)
    }

    private enum Column {
        static let date = "Date"
        static let model = "Model"
        static let inputWithCacheWrite = "Input (w/ Cache Write)"
        static let input = "Input (w/o Cache Write)"
        static let cacheRead = "Cache Read"
        static let output = "Output Tokens"
        static let required = [date, model, inputWithCacheWrite, input, cacheRead, output]
    }

    /// One event per row. "Input (w/ Cache Write)" is the prompt tokens
    /// that were written to the cache, "Input (w/o Cache Write)" the rest;
    /// both as OpenUsage reads them. A row with a broken date or count is
    /// skipped rather than counted as zero; a header missing a column is
    /// an export we do not understand and throws.
    static func events(fromCSV csv: String) throws -> [UsageEvent] {
        let rows = CSV.rows(csv)
        guard let header = rows.first else { return [] }
        var columns: [String: Int] = [:]
        for (index, name) in header.enumerated() {
            columns[name.trimmingCharacters(in: .whitespaces)] = index
        }
        guard Column.required.allSatisfy({ columns[$0] != nil }) else {
            throw ProviderError.requestFailed
        }
        func field(_ row: [String], _ name: String) -> String? {
            guard let index = columns[name], index < row.count else { return nil }
            return row[index].trimmingCharacters(in: .whitespaces)
        }
        return rows.dropFirst().compactMap { row in
            guard let timestamp = field(row, Column.date).flatMap(parseDate),
                  let model = field(row, Column.model), !model.isEmpty,
                  let cacheWrite = field(row, Column.inputWithCacheWrite).flatMap(count),
                  let input = field(row, Column.input).flatMap(count),
                  let cacheRead = field(row, Column.cacheRead).flatMap(count),
                  let output = field(row, Column.output).flatMap(count)
            else { return nil }
            return UsageEvent(
                model: CursorModelNames.canonical(model),
                timestamp: timestamp,
                tokens: TokenCount(input: input, cacheRead: cacheRead, cacheWrite5m: cacheWrite, output: output)
            )
        }
    }

    /// ISO 8601, or the export's older "yyyy-MM-dd HH:mm:ss" in UTC.
    private static func parseDate(_ text: String) -> Date? {
        if let date = UsageDate.parse(text) {
            return date
        }
        let parts = text.split(separator: " ")
        guard parts.count == 2 else { return nil }
        return UsageDate.parse("\(parts[0])T\(parts[1])Z")
    }

    /// An empty cell is zero; "1,234" is 1234; anything else is broken.
    private static func count(_ text: String) -> Int? {
        text.isEmpty ? 0 : Int(text.replacingOccurrences(of: ",", with: ""))
    }
}

/// Cursor names models its own way: `claude-4.5-sonnet-thinking`,
/// `gpt-5.6-sol-high`, `claude-opus-4-7-max-fast`. This folds the effort
/// and thinking tags away and puts Anthropic's ids in Anthropic's order,
/// so the price table finds them. Fast stays, it is priced apart.
nonisolated enum CursorModelNames {
    private static let effortTags = ["none", "low", "medium", "high", "xhigh", "extra-high", "max", "ultra", "thinking"]

    static func canonical(_ label: String) -> String {
        var name = label.lowercased().trimmingCharacters(in: .whitespaces)
        // "Claude Opus 4.5 (Max)" style labels from the router.
        name = name.replacingOccurrences(of: #"\s*\(.*\)$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: " ", with: "-")
        let fast = name.hasSuffix("-fast")
        if fast {
            name.removeLast("-fast".count)
        }
        var parts = name.split(separator: "-").map(String.init)
        while let last = parts.last, parts.count > 1, effortTags.contains(last) {
            parts.removeLast()
        }
        name = parts.joined(separator: "-")
        if name.hasPrefix("claude-") {
            // "claude-4.5-sonnet" is Anthropic's "claude-sonnet-4-5".
            name = name.replacingOccurrences(
                of: #"^claude-(\d+)(?:\.(\d+))?-(opus|sonnet|haiku)"#,
                with: "claude-$3-$1-$2",
                options: .regularExpression
            )
            .replacingOccurrences(of: "--", with: "-")
            .replacingOccurrences(of: ".", with: "-")
            while name.hasSuffix("-") {
                name.removeLast()
            }
        }
        return fast ? name + "-fast" : name
    }
}

/// Enough of RFC 4180 for the export: quoted fields, doubled quotes, CRLF.
nonisolated enum CSV {
    static func rows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var characters = text.makeIterator()
        var pending = characters.next()
        while let character = pending {
            pending = characters.next()
            if quoted {
                if character == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = characters.next()
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                quoted = true
            } else if character == "," {
                row.append(field)
                field = ""
            } else if character == "\n" || character == "\r\n" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
