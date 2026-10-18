import Foundation
@testable import Notchlet
import Testing

struct CodexHistorySourceTests {
    /// Real lines from a Codex 0.147 rollout, the system prompt removed.
    private static let sessionMeta = """
    {"timestamp":"2026-08-06T05:31:51.757Z","type":"session_meta","payload":{"id":"019fd58e-71a4-76d0-96e5-b0331fdcec26","timestamp":"2026-08-06T05:31:50.053Z","cwd":"/Users/me/project","originator":"Codex Desktop","cli_version":"0.147.0-alpha.1.2","source":"vscode","thread_source":"automation","base_instructions":{"text":"You are Codex."}}}
    """
    private static let taskStarted = """
    {"timestamp":"2026-08-06T05:31:51.784Z","type":"event_msg","payload":{"type":"task_started","turn_id":"019fd58e-7853","started_at":1785994311,"model_context_window":258400}}
    """
    private static let turnContext = """
    {"timestamp":"2026-08-06T05:31:53.107Z","type":"turn_context","payload":{"turn_id":"019fd58e-7853","cwd":"/Users/me/project","model":"gpt-5.6-luna","effort":"max","summary":"auto"}}
    """
    private static let firstCall = """
    {"timestamp":"2026-08-06T05:32:12.282Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":20677,"cached_input_tokens":9984,"cache_write_input_tokens":0,"output_tokens":974,"reasoning_output_tokens":395,"total_tokens":21651},"last_token_usage":{"input_tokens":20677,"cached_input_tokens":9984,"cache_write_input_tokens":0,"output_tokens":974,"reasoning_output_tokens":395,"total_tokens":21651},"model_context_window":258400},"rate_limits":null}}
    """
    private static let secondCall = """
    {"timestamp":"2026-08-06T05:32:26.043Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":55230,"cached_input_tokens":30208,"cache_write_input_tokens":0,"output_tokens":1689,"reasoning_output_tokens":567,"total_tokens":56919},"last_token_usage":{"input_tokens":34553,"cached_input_tokens":20224,"cache_write_input_tokens":0,"output_tokens":715,"reasoning_output_tokens":172,"total_tokens":35268},"model_context_window":258400},"rate_limits":null}}
    """
    private static let reasoning = """
    {"timestamp":"2026-08-06T05:32:00.000Z","type":"response_item","payload":{"type":"reasoning","summary":[{"type":"summary_text","text":"token_count is a word here"}]}}
    """

    private func events(_ lines: [String]) -> [UsageEvent] {
        var state = CodexLogParser.initialState
        return lines.compactMap { CodexLogParser.parse(Data($0.utf8), state: &state) }
    }

    @Test func eachCallIsItsTurnDeltaWithCachedTokensSplitOut() {
        let events = events([
            Self.sessionMeta,
            Self.taskStarted,
            Self.turnContext,
            Self.reasoning,
            Self.firstCall,
            Self.secondCall,
        ])

        #expect(events.count == 2)
        #expect(events.map(\.model) == ["gpt-5.6-luna", "gpt-5.6-luna"])
        #expect(events[0].tokens == TokenCount(input: 20677 - 9984, cacheRead: 9984, output: 974))
        #expect(events[1].tokens == TokenCount(input: 34553 - 20224, cacheRead: 20224, output: 715))
        #expect(events[1].timestamp == ISO8601DateFormatter().date(from: "2026-08-06T05:32:26Z"))
        #expect(events.allSatisfy { $0.id == nil })
    }

    @Test func aRepeatedTotalIsNotASecondCall() {
        let events = events([Self.turnContext, Self.firstCall, Self.firstCall, Self.secondCall])
        #expect(events.count == 2)
    }

    @Test func withoutADeltaTheTotalsDifferenceCounts() {
        let stripped = [Self.firstCall, Self.secondCall].map {
            $0.replacingOccurrences(of: #""last_token_usage":\{[^}]*\},"#, with: "", options: .regularExpression)
        }
        let events = events([Self.turnContext] + stripped)

        #expect(events.count == 2)
        #expect(events[0].tokens == TokenCount(input: 20677 - 9984, cacheRead: 9984, output: 974))
        #expect(events[1].tokens == TokenCount(input: 34553 - 20224, cacheRead: 20224, output: 715))
    }

    @Test func aCallBeforeAnyTurnContextHasNoModel() {
        let events = events([Self.firstCall])
        #expect(events.count == 1)
        #expect(events[0].model == nil)
    }

    @Test func skipsLinesWithoutUsage() {
        let nullInfo = """
        {"timestamp":"2026-08-05T08:27:06.927Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex"}}}
        """
        #expect(events([Self.turnContext, nullInfo, Self.reasoning, "", "not json"]).isEmpty)
    }

    @Test func aChildThreadDropsTheReplayOfItsParent() {
        let child = Self.sessionMeta.replacingOccurrences(
            of: #""thread_source":"automation""#,
            with: #""thread_source":"subagent""#
        )
        // Replayed before the thread's own first turn starts.
        let replayed = Self.firstCall.replacingOccurrences(
            of: "2026-08-06T05:32:12.282Z",
            with: "2026-08-06T05:31:50.900Z"
        )
        let events = events([child, Self.turnContext, replayed, Self.taskStarted, Self.secondCall])

        #expect(events.count == 1)
        #expect(events[0].tokens == TokenCount(input: 34553 - 20224, cacheRead: 20224, output: 715))
    }

    @Test func aForkedThreadIsAChildToo() {
        let forked = Self.sessionMeta.replacingOccurrences(
            of: #""source":"vscode""#, with: #""source":"vscode","forked_from_id":"019fd58e-0000""#
        )
        #expect(events([forked, Self.turnContext, Self.firstCall]).isEmpty)
        #expect(events([forked, Self.turnContext, Self.taskStarted, Self.firstCall]).count == 1)

        let nested = Self.sessionMeta.replacingOccurrences(
            of: #""source":"vscode""#, with: #""source":{"subagent":{"other":"guardian"}}"#
        )
        #expect(events([nested, Self.turnContext, Self.firstCall]).isEmpty)
    }

    @Test func liveSessionsWinOverArchivedCopies() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "notchlet-codex-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appending(path: "sessions/2026/08/06")
        let archived = root.appending(path: "archived_sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        let thread = [Self.sessionMeta, Self.turnContext, Self.firstCall].joined(separator: "\n") + "\n"
        try Data(thread.utf8).write(to: sessions.appending(path: "rollout-a.jsonl"))
        try Data(thread.utf8).write(to: archived.appending(path: "rollout-a.jsonl"))
        try Data(thread.utf8).write(to: archived.appending(path: "rollout-b.jsonl"))

        let source = CodexHistorySource(roots: [root.appending(path: "sessions"), archived])
        let events = try await source.events(since: nil)

        #expect(events.count == 2)
    }
}
