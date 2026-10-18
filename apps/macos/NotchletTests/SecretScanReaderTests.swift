import Foundation
@testable import Notchlet
import Testing

struct SecretScanReaderTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "notchlet-scan-reader-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    @Test func appendsReplayContextAndPreserveOriginalLocations() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "a.jsonl")
        try Data("first\nsecond\n".utf8).write(to: file)
        let first = try #require(await SecretScanReader(urls: [file], checkpoints: [:]).next())
        let checkpoint = try #require(first.portions.last?.checkpoint)
        #expect(try await SecretScanReader(urls: [file], checkpoints: [file.path: checkpoint]).next() == nil)

        try append("new-key\n", to: file)
        let batch = try #require(await SecretScanReader(urls: [file], checkpoints: [file.path: checkpoint]).next())
        #expect(String(decoding: batch.data, as: UTF8.self) == "second\nnew-key\n")
        let match = SecretMatch(ruleID: "test", description: "key", secret: "new-key", line: 2)
        #expect(batch.locate([match]).first?.line == 3)
        #expect(batch.locate([match]).first?.file == file)
        #expect(batch.portions.last?.checkpoint.offset == 21)
    }

    @Test func splitKeyWaitsForACompleteRecord() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "partial.jsonl")
        try Data("old\nsecret-half".utf8).write(to: file)
        let first = try #require(await SecretScanReader(urls: [file], checkpoints: [:]).next())
        let checkpoint = try #require(first.portions.first?.checkpoint)
        #expect(String(decoding: first.data, as: UTF8.self) == "old\n")
        #expect(checkpoint.offset == 4)
        #expect(try await SecretScanReader(urls: [file], checkpoints: [file.path: checkpoint]).next() == nil)
        try append("-completed\n", to: file)
        let second = try #require(await SecretScanReader(urls: [file], checkpoints: [file.path: checkpoint]).next())
        #expect(String(decoding: second.data, as: UTF8.self) == "old\nsecret-half-completed\n")
        #expect(second.portions.first?.checkpoint.line == 2)
    }

    @Test func checkpointsResumeAnInterruptedUnchangedFile() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "large.jsonl")
        try Data("one\ntwo\nthree\nfour\n".utf8).write(to: file)
        let first = try #require(await SecretScanReader(urls: [file], checkpoints: [:], targetBytes: 8).next())
        let checkpoint = try #require(first.portions.last?.checkpoint)
        #expect(checkpoint.offset == 8)
        let resumed = try #require(await SecretScanReader(urls: [file], checkpoints: [file.path: checkpoint]).next())
        #expect(String(decoding: resumed.data, as: UTF8.self) == "two\nthree\nfour\n")
        #expect(resumed.portions.last?.checkpoint.line == 4)
    }

    @Test func replacingTruncatingOrRewritingAFileRestartsIt() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "a.jsonl")
        try Data("original\n".utf8).write(to: file)
        let first = try #require(await SecretScanReader(urls: [file], checkpoints: [:]).next())
        let checkpoint = try #require(first.portions.first?.checkpoint)
        for (text, atomic) in [("short\n", false), ("rewritten-longer\n", false), ("replaced-completely\n", true)] {
            try Data(text.utf8).write(to: file, options: atomic ? .atomic : [])
            let batch = try #require(await SecretScanReader(urls: [file], checkpoints: [file.path: checkpoint]).next())
            #expect(String(decoding: batch.data, as: UTF8.self) == text)
            #expect(batch.portions.first?.firstLine == 1)
        }
    }

    @Test func batchesManyFilesAndMapsTheirLineNumbers() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = (0 ..< 3).map { directory.appending(path: "\($0).jsonl") }
        for file in files {
            try Data("one\ntwo\n".utf8).write(to: file)
        }
        let reader = SecretScanReader(urls: files, checkpoints: [:], targetBytes: 12)
        var checkpoints: [String: SecretFileCheckpoint] = [:]
        var seen: Set<String> = []
        while let batch = try await reader.next() {
            for portion in batch.portions {
                checkpoints[portion.url.path] = portion.checkpoint
                let match = SecretMatch(
                    ruleID: "test",
                    description: "key",
                    secret: "key",
                    line: portion.lines.lowerBound
                )
                let located = try #require(batch.locate([match]).first)
                #expect(located.line == portion.firstLine)
                #expect(located.file == portion.url)
                seen.insert(portion.url.path)
            }
        }
        #expect(seen == Set(files.map(\.path)))
        #expect(checkpoints.values.allSatisfy { $0.offset == 8 && $0.line == 2 })
    }

    @Test func aRecordLargerThanTheBatchTargetIsNotSplitOrSkipped() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "long.jsonl")
        let long = String(repeating: "x", count: LineReader.chunkSize * 5) + "\n"
        try Data((long + "tail\n").utf8).write(to: file)
        let reader = SecretScanReader(urls: [file], checkpoints: [:], targetBytes: 1024)
        let first = try #require(await reader.next())
        #expect(first.data == Data(long.utf8))
        let second = try #require(await reader.next())
        #expect(second.data == Data((long + "tail\n").utf8))
        #expect(try await reader.next() == nil)
    }

    @Test func cancellationDoesNotProduceACheckpoint() async throws {
        let reader = SecretScanReader(urls: [URL(filePath: "/missing.jsonl")], checkpoints: [:])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await reader.next()
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func realScannerFindsTheSameKeysAfterAnAppendAcrossABatchBoundary() async throws {
        guard Betterleaks.isAvailable else { return }
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "keys.jsonl")
        let firstKey = "ghp_4eC39HqLyjWDarjtT1zdp7dcQ6vN8sK2aY5B"
        let secondKey = "ghp_9fD47JmNzqXEbsktU2aeq8edR7wP3tL6bZ1C"
        try Data("{\"text\":\"\(firstKey)\"}\n".utf8).write(to: file)
        let initial = try #require(await SecretScanReader(urls: [file], checkpoints: [:]).next())
        let checkpoint = try #require(initial.portions.first?.checkpoint)
        try append("{\"text\":\"\(secondKey)\"}\n", to: file)
        let reader = SecretScanReader(urls: [file], checkpoints: [file.path: checkpoint], targetBytes: 20)
        var incremental: [SecretMatch] = []
        while let batch = try await reader.next() {
            try await incremental += batch.locate(Betterleaks.scan(.text(batch.data)))
        }
        let full = try await Betterleaks.scan(.files([file]))
        #expect(Set(full.map(\.secret)) == [firstKey, secondKey])
        #expect(Set(incremental.map(\.secret)) == Set(full.map(\.secret)))
        #expect(incremental.first { $0.secret == secondKey }?.line == 2)
        #expect(incremental.allSatisfy { $0.file == file })
    }

    @Test func oldStateMigratesAndRuleChangesResetProgress() throws {
        var state = try JSONDecoder().decode(
            SecretScanState.self,
            from: Data(#"{"version":1,"findings":[],"lastScanAt":{"p":1}}"#.utf8)
        )
        #expect(state.checkpoints.isEmpty)
        state.useRules("new-rules")
        #expect(state.lastScanAt.isEmpty)
        #expect(state.rulesVersion == "new-rules")
        #expect(try JSONDecoder().decode(SecretScanState.self, from: JSONEncoder().encode(state)) == state)
    }

    @Test func appendingOneKiBToASixteenMiBLogScansOnlyTwoRecords() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "many-records.jsonl")
        let record = Data((String(repeating: "x", count: 1023) + "\n").utf8)
        var original = Data()
        for _ in 0 ..< 16384 {
            original.append(record)
        }
        try original.write(to: file)
        let reader = SecretScanReader(urls: [file], checkpoints: [:])
        var checkpoint: SecretFileCheckpoint?
        while let batch = try await reader.next() {
            #expect(batch.data.count <= 4 * 1024 * 1024)
            checkpoint = batch.portions.last?.checkpoint
        }
        let saved = try #require(checkpoint)
        try append(String(decoding: record, as: UTF8.self), to: file)
        let incremental = SecretScanReader(urls: [file], checkpoints: [file.path: saved])
        let batch = try #require(await incremental.next())
        #expect(batch.data.count == 2048)
        #expect(batch.portions.first?.checkpoint.line == 16385)
        #expect(try await incremental.next() == nil)
    }
}
