import Foundation

/// OpenCode's message store as a history source.
///
/// OpenCode keeps every message in SQLite under its data directory, one
/// database per release channel (`opencode.db`, `opencode-next.db`), as a
/// JSON `data` column. Assistant messages carry the model, the token
/// counts and the cost OpenCode computed itself. Only the gateways
/// OpenCode bills (Go and Zen) count: a message through the user's own
/// API key is that vendor's bill, not OpenCode usage. Read through
/// `sqlite3` read-only, like Cursor's token, so the app's database is
/// never locked or modified.
nonisolated struct OpenCodeHistorySource: UsageHistorySource {
    static let defaultDataDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".local/share/opencode")
    static let hostedProviderIDs = ["opencode-go", "opencode"]

    let dataDirectory: URL

    init(dataDirectory: URL = Self.defaultDataDirectory) {
        self.dataDirectory = dataDirectory
    }

    func events(since: Date?) async throws -> [UsageEvent] {
        var events: [UsageEvent] = []
        for database in Self.databases(in: dataDirectory) {
            guard let rows = await CredentialSupport.sqliteRows(path: database, sql: Self.sql(since: since)) else {
                throw UsageProviderError.requestFailed
            }
            events += try Self.events(fromRows: rows)
        }
        return events
    }

    /// Every `opencode*.db` in the directory, so a preview channel counts
    /// too. Nothing at all when OpenCode has never run.
    static func databases(in directory: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix("opencode") && $0.hasSuffix(".db") }.sorted()
            .map { directory.appending(path: $0) }
    }

    static func sql(since: Date?) -> String {
        let cutoff = since.map { Int($0.timeIntervalSince1970 * 1000) } ?? 0
        let providers = hostedProviderIDs.map { "'\($0)'" }.joined(separator: ",")
        return """
        SELECT time_created AS ms,
               json_extract(data, '$.modelID') AS model,
               json_extract(data, '$.cost') AS cost,
               json_extract(data, '$.tokens.input') AS input,
               json_extract(data, '$.tokens.output') AS output,
               json_extract(data, '$.tokens.reasoning') AS reasoning,
               json_extract(data, '$.tokens.cache.read') AS cacheRead,
               json_extract(data, '$.tokens.cache.write') AS cacheWrite
        FROM message
        WHERE time_created >= \(cutoff)
          AND json_valid(data)
          AND json_extract(data, '$.role') = 'assistant'
          AND json_extract(data, '$.providerID') IN (\(providers));
        """
    }

    /// The rows as `sqlite3 -json` prints them. A cost of zero means
    /// OpenCode did not price the message (a plan that includes it), so
    /// the price table gets its turn; a positive cost is authoritative.
    static func events(fromRows data: Data) throws -> [UsageEvent] {
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([Row].self, from: data).map { row in
            UsageEvent(
                model: row.model,
                timestamp: Date(timeIntervalSince1970: row.ms / 1000),
                tokens: TokenCount(
                    input: row.input ?? 0,
                    cacheRead: row.cacheRead ?? 0,
                    cacheWrite5m: row.cacheWrite ?? 0,
                    output: (row.output ?? 0) + (row.reasoning ?? 0)
                ),
                reportedCost: row.cost.flatMap { $0 > 0 ? $0 : nil }
            )
        }
    }

    private struct Row: Decodable {
        var ms: Double
        var model: String?
        var cost: Double?
        var input: Int?
        var output: Int?
        var reasoning: Int?
        var cacheRead: Int?
        var cacheWrite: Int?
    }
}
