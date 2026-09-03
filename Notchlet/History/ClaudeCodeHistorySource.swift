import Foundation

/// Claude Code's transcripts as a history source.
///
/// Every session is a JSONL file under `~/.claude/projects/<project>/`, and
/// every subagent a file under `<session>/subagents/`. Each API reply is an
/// `assistant` line carrying the model, the message id and the usage as
/// the API returned it. Claude Code deletes transcripts after 30 days by
/// default (`cleanupPeriodDays`), which is why the archive exists.
nonisolated struct ClaudeCodeHistorySource: UsageHistorySource {
    static let defaultProjectsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/projects")

    private let reader: LogDirectoryReader<ClaudeCodeLogParser>

    init(projectsDirectory: URL = Self.defaultProjectsDirectory) {
        reader = LogDirectoryReader(roots: [projectsDirectory])
    }

    func events(since: Date?) async throws -> [UsageEvent] {
        try await reader.events(since: since)
    }
}

/// One transcript line.
///
/// A reply with several content blocks is written as one line per block,
/// each repeating the message id and the full usage, so the event id is the
/// message id and the rollup keeps one per id. `<synthetic>` is Claude
/// Code's own filler (an error notice, a compaction summary) and never a
/// billed request. Cache writes come split by tier when the line has
/// `cache_creation`; older lines only have the total, all of it 5-minute.
nonisolated enum ClaudeCodeLogParser: LogLineParser {
    struct State: Sendable {}

    static var initialState: State { State() }

    /// Only assistant lines carry this; user lines, attachments and
    /// bookkeeping records are skipped before any JSON is decoded.
    private static let marker = Data("\"usage\":{".utf8)

    static func parse(_ line: Data, state: inout State) -> UsageEvent? {
        guard line.range(of: marker) != nil, let record = try? JSONDecoder().decode(Line.self, from: line),
              record.type == "assistant", let message = record.message, let usage = message.usage,
              message.model != "<synthetic>", let timestamp = UsageDate.parse(record.timestamp)
        else { return nil }
        let tokens = TokenCount(
            input: usage.inputTokens ?? 0,
            cacheRead: usage.cacheReadInputTokens ?? 0,
            cacheWrite5m: usage.cacheCreation?.ephemeral5m ?? usage.cacheCreationInputTokens ?? 0,
            cacheWrite1h: usage.cacheCreation?.ephemeral1h ?? 0,
            output: usage.outputTokens ?? 0
        )
        return UsageEvent(
            id: message.id ?? record.requestId,
            model: message.model,
            timestamp: timestamp,
            tokens: tokens,
            reportedCost: record.costUSD
        )
    }

    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                struct CacheCreation: Decodable {
                    var ephemeral5m: Int?
                    var ephemeral1h: Int?

                    enum CodingKeys: String, CodingKey {
                        case ephemeral5m = "ephemeral_5m_input_tokens"
                        case ephemeral1h = "ephemeral_1h_input_tokens"
                    }
                }

                var inputTokens: Int?
                var outputTokens: Int?
                var cacheReadInputTokens: Int?
                var cacheCreationInputTokens: Int?
                var cacheCreation: CacheCreation?

                enum CodingKeys: String, CodingKey {
                    case inputTokens = "input_tokens"
                    case outputTokens = "output_tokens"
                    case cacheReadInputTokens = "cache_read_input_tokens"
                    case cacheCreationInputTokens = "cache_creation_input_tokens"
                    case cacheCreation = "cache_creation"
                }
            }

            var id: String?
            var model: String?
            var usage: Usage?
        }

        var type: String
        var timestamp: String
        var message: Message?
        var requestId: String?
        var costUSD: Double?
    }
}
