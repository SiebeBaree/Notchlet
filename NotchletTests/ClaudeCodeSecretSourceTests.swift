import Foundation
@testable import Notchlet
import Testing

struct ClaudeCodeSecretSourceTests {
    @Test func listsTranscriptsAndSubagentsChangedSince() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "notchlet-secrets-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appending(path: "-Users-me-project/abc")
        try FileManager.default.createDirectory(
            at: session.appending(path: "subagents"),
            withIntermediateDirectories: true
        )
        let transcript = root.appending(path: "-Users-me-project/abc.jsonl")
        let subagent = session.appending(path: "subagents/agent-1.jsonl")
        let stale = root.appending(path: "-Users-me-project/old.jsonl")
        for file in [transcript, subagent, stale] {
            try Data("{}\n".utf8).write(to: file)
        }
        try Data("ignored".utf8).write(to: root.appending(path: "-Users-me-project/notes.txt"))
        let lastWeek = Date.now.addingTimeInterval(-7 * 24 * 3600)
        try FileManager.default.setAttributes([.modificationDate: lastWeek], ofItemAtPath: stale.path)

        let source = ClaudeCodeSecretSource(projectsDirectory: root)
        guard case let .files(everything) = try await source.input(since: nil) else {
            Issue.record("expected files")
            return
        }
        #expect(Set(everything.map(\.lastPathComponent)) == ["abc.jsonl", "agent-1.jsonl", "old.jsonl"])

        guard case let .files(recent) = try await source.input(since: Date.now.addingTimeInterval(-3600)) else {
            Issue.record("expected files")
            return
        }
        #expect(Set(recent.map(\.lastPathComponent)) == ["abc.jsonl", "agent-1.jsonl"])
    }
}
