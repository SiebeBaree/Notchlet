import Foundation

/// Codex's session rollouts as a history source.
///
/// Every thread is a JSONL file under `~/.codex/sessions/YYYY/MM/DD/`, or
/// under `archived_sessions/` once archived. The CLI writes an event per
/// API call with the turn's token delta and the running total, and the
/// model on a separate `turn_context` line before it. Codex keeps sessions
/// forever, so on this source the archive only saves re-reading.
nonisolated struct CodexHistorySource: UsageHistorySource {
    static let defaultRoots = [".codex/sessions", ".codex/archived_sessions"].map {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: $0)
    }

    private let reader: LogDirectoryReader<CodexLogParser>

    /// Roots in order of preference: a thread present under both keeps the
    /// live copy.
    init(roots: [URL] = Self.defaultRoots) {
        reader = LogDirectoryReader(roots: roots)
    }

    func events(since: Date?) async throws -> [UsageEvent] {
        try await reader.events(since: since)
    }
}

/// One rollout line, with the state a thread needs across lines.
///
/// `token_count` carries `last_token_usage`, the delta for the call, and
/// `total_token_usage`, the running total. The delta is what counts; the
/// total is the fallback for older rollouts and the way a re-emitted
/// snapshot (same total twice) is told from a real call. Codex counts
/// cached tokens inside its input, so they are subtracted out into the
/// cache-read bucket; reasoning tokens are already inside output.
///
/// A subagent or forked thread starts by replaying its parent's history
/// with fresh timestamps. Those events only seed the running total and
/// are dropped until the thread's first `task_started` at or after its own
/// creation, which is when its own calls begin. OpenUsage documents a 20x
/// inflation from counting the replay.
nonisolated enum CodexLogParser: LogLineParser {
    struct State: Sendable {
        var model: String?
        var previousTotal: Totals?
        /// False while a child thread is still replaying its parent.
        var isLive = true
        /// The thread's creation, epoch seconds, from `session_meta`.
        var createdAt: TimeInterval?
    }

    struct Totals: Decodable, Equatable, Sendable {
        var inputTokens = 0
        var cachedInputTokens = 0
        var outputTokens = 0

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case cachedInputTokens = "cached_input_tokens"
            case outputTokens = "output_tokens"
        }

        static func - (lhs: Totals, rhs: Totals) -> Totals {
            Totals(
                inputTokens: max(lhs.inputTokens - rhs.inputTokens, 0),
                cachedInputTokens: max(lhs.cachedInputTokens - rhs.cachedInputTokens, 0),
                outputTokens: max(lhs.outputTokens - rhs.outputTokens, 0)
            )
        }
    }

    static var initialState: State { State() }

    private static let markers = [
        Data(#""type":"token_count""#.utf8),
        Data(#""type":"turn_context""#.utf8),
        Data(#""type":"session_meta""#.utf8),
        Data(#""type":"task_started""#.utf8),
    ]

    static func parse(_ line: Data, state: inout State) -> UsageEvent? {
        guard markers.contains(where: { line.range(of: $0) != nil }),
              let record = try? JSONDecoder().decode(Line.self, from: line)
        else { return nil }
        switch record.type {
        case "session_meta":
            readSessionMeta(line, into: &state)
        case "turn_context":
            if let model = record.payload?.model ?? record.payload?.modelName {
                state.model = model
            }
        case "event_msg" where record.payload?.type == "task_started":
            if !state.isLive, let startedAt = record.payload?.startedAt,
               startedAt >= (state.createdAt ?? 0).rounded(.down)
            {
                state.isLive = true
            }
        case "event_msg" where record.payload?.type == "token_count":
            return tokenCount(record, state: &state)
        default:
            break
        }
        return nil
    }

    private static func tokenCount(_ record: Line, state: inout State) -> UsageEvent? {
        guard let info = record.payload?.info, let total = info.totalTokenUsage else { return nil }
        defer { state.previousTotal = total }
        guard state.isLive, total != state.previousTotal else { return nil }
        let delta = info.lastTokenUsage ?? state.previousTotal.map { total - $0 } ?? total
        let cached = min(delta.cachedInputTokens, delta.inputTokens)
        let tokens = TokenCount(input: delta.inputTokens - cached, cacheRead: cached, output: delta.outputTokens)
        guard tokens.total > 0, let timestamp = UsageDate.parse(record.timestamp) else { return nil }
        return UsageEvent(model: state.model, timestamp: timestamp, tokens: tokens)
    }

    /// The line is large (it carries the system prompt) and its shape
    /// varies by version, so it is read once as a dictionary rather than
    /// modeled.
    private static func readSessionMeta(_ line: Data, into state: inout State) {
        guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = record["payload"] as? [String: Any]
        else { return }
        if let created = (payload["timestamp"] as? String).flatMap(UsageDate.parse) {
            state.createdAt = created.timeIntervalSince1970
        }
        let source = payload["source"]
        let isChild = payload["thread_source"] as? String == "subagent"
            || payload["forked_from_id"] is String
            || payload["parent_thread_id"] is String
            || source as? String == "subagent"
            || (source as? [String: Any])?["subagent"] != nil
        if isChild {
            state.isLive = false
        }
    }

    private struct Line: Decodable {
        struct Payload: Decodable {
            struct Info: Decodable {
                var totalTokenUsage: Totals?
                var lastTokenUsage: Totals?

                enum CodingKeys: String, CodingKey {
                    case totalTokenUsage = "total_token_usage"
                    case lastTokenUsage = "last_token_usage"
                }
            }

            var type: String?
            var model: String?
            var modelName: String?
            var info: Info?
            var startedAt: TimeInterval?

            enum CodingKeys: String, CodingKey {
                case type, model, info
                case modelName = "model_name"
                case startedAt = "started_at"
            }
        }

        var type: String
        var timestamp: String
        var payload: Payload?
    }
}
