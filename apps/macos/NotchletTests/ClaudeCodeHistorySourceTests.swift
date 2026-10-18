import Foundation
@testable import Notchlet
import Testing

struct ClaudeCodeHistorySourceTests {
    /// A real assistant line from Claude Code 2.1, content removed.
    private let assistantLine = """
    {"parentUuid":"bc1c798c","isSidechain":false,"message":{"model":"claude-fable-5-1","id":"msg_011Ceg2LXENYe8zMTDKniJRY","type":"message","role":"assistant","content":[{"type":"text","text":"\\"usage\\":{ in the prose"}],"stop_reason":"tool_use","usage":{"input_tokens":2,"cache_creation_input_tokens":16256,"cache_read_input_tokens":11471,"output_tokens":749,"output_tokens_details":{"thinking_tokens":422},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":16000,"ephemeral_5m_input_tokens":256},"speed":"standard"}},"requestId":"req_011Ceg2LWBNcmufMEtnnjGf3","type":"assistant","uuid":"54b7f928","timestamp":"2026-09-03T06:21:46.561Z","sessionId":"4b31e110","version":"2.1.259"}
    """

    private func parse(_ line: String) -> UsageEvent? {
        var state = ClaudeCodeLogParser.initialState
        return ClaudeCodeLogParser.parse(Data(line.utf8), state: &state)
    }

    @Test func parsesAnAssistantLine() throws {
        let event = try #require(parse(assistantLine))
        #expect(event.id == "msg_011Ceg2LXENYe8zMTDKniJRY")
        #expect(event.model == "claude-fable-5-1")
        #expect(event.timestamp == ISO8601DateFormatter().date(from: "2026-09-03T06:21:46Z"))
        #expect(event.tokens == TokenCount(
            input: 2,
            cacheRead: 11471,
            cacheWrite5m: 256,
            cacheWrite1h: 16000,
            output: 749
        ))
        #expect(event.reportedCost == nil)
    }

    @Test func legacyCacheCreationCountsAsFiveMinute() throws {
        let line = """
        {"type":"assistant","timestamp":"2025-06-01T10:00:00.000Z","requestId":"req_1","costUSD":0.0123,"message":{"id":"msg_old","model":"claude-sonnet-4-20250514","usage":{"input_tokens":10,"cache_creation_input_tokens":500,"cache_read_input_tokens":0,"output_tokens":20}}}
        """
        let event = try #require(parse(line))
        #expect(event.tokens == TokenCount(input: 10, cacheRead: 0, cacheWrite5m: 500, cacheWrite1h: 0, output: 20))
        #expect(event.reportedCost == 0.0123)
    }

    @Test func skipsLinesWithoutBilledUsage() {
        let user = """
        {"type":"user","timestamp":"2026-09-03T06:21:40.000Z","message":{"role":"user","content":"paste: \\"usage\\":{\\"input_tokens\\":1}"}}
        """
        let synthetic = """
        {"type":"assistant","timestamp":"2026-09-03T06:21:46.561Z","message":{"model":"<synthetic>","id":"msg_x","usage":{"input_tokens":0,"output_tokens":0}}}
        """
        let attachment = #"{"type":"attachment","timestamp":"2026-09-03T06:21:46.561Z","attachment":{}}"#
        #expect(parse(user) == nil)
        #expect(parse(synthetic) == nil)
        #expect(parse(attachment) == nil)
        #expect(parse("not json") == nil)
        #expect(parse("") == nil)
    }

    @Test func readsATranscriptTreeIncludingSubagents() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "notchlet-claude-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appending(path: "-Users-me-project/abc")
        try FileManager.default.createDirectory(
            at: session.appending(path: "subagents"),
            withIntermediateDirectories: true
        )
        // The same message twice in the session file, once per content block.
        try Data((assistantLine + "\n" + assistantLine + "\n").utf8)
            .write(to: root.appending(path: "-Users-me-project/abc.jsonl"))
        let subagentLine = assistantLine.replacingOccurrences(of: "msg_011Ceg2LXENYe8zMTDKniJRY", with: "msg_sub")
        try Data((subagentLine + "\n").utf8).write(to: session.appending(path: "subagents/agent-1.jsonl"))
        try Data("ignored".utf8).write(to: root.appending(path: "-Users-me-project/notes.txt"))

        let events = try await ClaudeCodeHistorySource(projectsDirectory: root).events(since: nil)

        #expect(events.count == 3)
        #expect(Set(UsageRollup.deduplicated(events).map(\.id)) == ["msg_011Ceg2LXENYe8zMTDKniJRY", "msg_sub"])
    }
}
