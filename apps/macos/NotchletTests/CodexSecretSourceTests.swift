import Foundation
@testable import Notchlet
import Testing

struct CodexSecretSourceTests {
    @Test func liveSessionsWinOverArchivedCopies() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "notchlet-codex-secrets-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let live = root.appending(path: "sessions/2026/06/22")
        let archived = root.appending(path: "archived_sessions")
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        for file in [
            live.appending(path: "rollout-a.jsonl"),
            archived.appending(path: "rollout-a.jsonl"),
            archived.appending(path: "rollout-b.jsonl"),
        ] {
            try Data("{}\n".utf8).write(to: file)
        }

        let source = CodexSecretSource(roots: [root.appending(path: "sessions"), archived])
        guard case let .files(files) = try await source.input(since: nil) else {
            Issue.record("expected files")
            return
        }
        // The enumerator resolves /var to /private/var, so compare tails.
        let tails = Set(files.map { $0.pathComponents.suffix(2).joined(separator: "/") })
        #expect(tails == ["22/rollout-a.jsonl", "archived_sessions/rollout-b.jsonl"])
    }
}
