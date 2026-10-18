import Foundation
@testable import Notchlet
import Testing

nonisolated struct BetterleaksTests {
    @Test(arguments: [0, 1, 256, 257, 5580])
    func batchesEveryPathOnce(count: Int) {
        let urls = (0 ..< count).map { URL(filePath: "/tmp/session-\($0).jsonl") }
        let batches = Betterleaks.fileBatches(urls)

        #expect(batches.flatMap(\.self) == urls.map(\.path))
        #expect(batches.allSatisfy { !$0.isEmpty && $0.count <= 256 })
    }

    @Test func batchesLongPathsByUTF8Bytes() {
        let directory = Array(repeating: String(repeating: "é", count: 100), count: 4).joined(separator: "/")
        let urls = (0 ..< 200).map { URL(filePath: "/tmp/\(directory)/session-\($0).jsonl") }
        let batches = Betterleaks.fileBatches(urls)

        #expect(batches.count > 1)
        #expect(batches.flatMap(\.self) == urls.map(\.path))
        #expect(batches.allSatisfy { $0.reduce(0) { $0 + $1.utf8.count + 1 } <= 128 * 1024 })
    }

    @Test func collectsMatchesFromAll5580Files() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = try scanner(in: directory)
        let urls = (0 ..< 5580).map { URL(filePath: "/tmp/Claude sessions/agent-\($0).jsonl") }

        let matches = try await Betterleaks.scan(.files(urls), executable: executable)

        #expect(matches.map(\.file) == urls.map(Optional.some))
        #expect(matches.allSatisfy { $0.line == 7 && $0.ruleID == "test-key" })
    }

    @Test func aLaterBatchFailureFailsTheWholeScan() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = try scanner(in: directory)
        let urls = (0 ..< 500).map { URL(filePath: "/tmp/agent-\($0).jsonl") } + [URL(filePath: "/tmp/fail.jsonl")]

        do {
            _ = try await Betterleaks.scan(.files(urls), executable: executable)
            Issue.record("A failed batch must not return partial matches")
        } catch Betterleaks.ScanError.failed(status: 7) {
            let calls = try String(contentsOf: executable.appendingPathExtension("calls"), encoding: .utf8)
            #expect(calls.split(separator: "\n").count > 1)
        }
    }

    @Test func aCleanBatchDoesNotDiscardLaterMatches() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = try scanner(in: directory)
        let matched = URL(filePath: "/tmp/matched.jsonl")
        let urls = (0 ..< 256).map { URL(filePath: "/tmp/clean-\($0).jsonl") } + [matched]

        let matches = try await Betterleaks.scan(.files(urls), executable: executable)

        #expect(matches.map(\.file) == [matched])
    }

    @Test func cancellationStopsBeforeLaunchingABatch() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = try scanner(in: directory)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await Betterleaks.scan(.files([URL(filePath: "/tmp/agent.jsonl")]), executable: executable)
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: executable.appendingPathExtension("calls").path))
    }

    @Test func emptyFileListDoesNotLaunchTheScanner() async throws {
        let matches = try await Betterleaks.scan(.files([]), executable: URL(filePath: "/missing-scanner"))
        #expect(matches.isEmpty)
    }

    @Test func textStillGoesThroughStandardInput() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = try scanner(in: directory)
        let report = Data("""
        [{"RuleID":"test-key","Description":"Test key","Secret":"fake","StartLine":3,"File":""}]
        """.utf8)

        let matches = try await Betterleaks.scan(.text(report), executable: executable)

        #expect(matches.count == 1)
        #expect(matches.first?.line == 3)
        #expect(matches.first?.file == nil)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "notchlet-batches-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Reports each supplied path, so missing a batch loses observable matches.
    private func scanner(in directory: URL) throws -> URL {
        let executable = directory.appending(path: "scanner")
        let script = #"""
        #!/bin/sh
        if [ "$1" = stdin ]; then exec /bin/cat; fi
        [ "$1" = dir ] || exit 8
        shift
        printf 'scan\n' >> "$0.calls"
        case "$1" in /tmp/clean-*) printf null; exit 0 ;; esac
        printf '['
        comma=''
        for file do
            case "$file" in
                --*) break ;;
                */fail.jsonl) exit 7 ;;
            esac
            printf '%s{"RuleID":"test-key","Description":"Test key","Secret":"fake","StartLine":7,"File":"%s"}' "$comma" "$file"
            comma=','
        done
        printf ']'
        """#
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return executable
    }
}
