import Foundation
@testable import Notchlet
import Testing

/// The line reader and the per-file cache, through a parser that counts
/// every non-empty line as one event.
struct LogDirectoryReaderTests {
    private nonisolated enum DatedCounter: LogLineParser {
        struct State: Sendable { var count = 0 }
        static var initialState: State { State() }
        static func parse(_ line: Data, state: inout State) -> UsageEvent? {
            state.count += 1
            guard let seconds = Double(String(decoding: line, as: UTF8.self)) else { return nil }
            return UsageEvent(timestamp: Date(timeIntervalSince1970: seconds), tokens: TokenCount(output: state.count))
        }
    }

    @Test func sealedEventsAreEvictedWhileAppendParserStateSurvives() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "dates.jsonl")
        try Data("100\n200\n".utf8).write(to: file)
        let reader = LogDirectoryReader<DatedCounter>(roots: [directory])
        #expect(try await reader.events(since: nil).count == 2)
        let revision = await reader.revision
        await reader.discardEvents(before: Date(timeIntervalSince1970: 150))
        let live = try await reader.events(since: nil)
        #expect(live.map(\.tokens.output) == [2])
        #expect(await reader.revision == revision)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("100\n300\n".utf8))
        try handle.close()
        let appended = try await reader.events(since: nil)
        #expect(appended.map(\.tokens.output) == [2, 4])
        #expect(await reader.revision != revision)
    }

    @Test func longRecordsRemainIntactAndCancellationStopsBetweenLines() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "long.jsonl")
        let length = 16 * 1024 * 1024
        try Data((String(repeating: "x", count: length) + "\ntail\n").utf8).write(to: file)
        var lengths: [Int] = []
        let offset = try LineReader.forEachLine(in: file, from: 0) { lengths.append($0.count) }
        #expect(lengths == [length, 4])
        #expect(offset == UInt64(length + 6))
        let task = Task {
            try LineReader.forEachLine(in: file, from: 0) { _ in withUnsafeCurrentTask { $0?.cancel() } }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private enum LineCounter: LogLineParser {
        struct State: Sendable {
            var lines = 0
        }

        static var initialState: State { State() }

        static func parse(_ line: Data, state: inout State) -> UsageEvent? {
            guard !line.isEmpty else { return nil }
            state.lines += 1
            return UsageEvent(
                model: String(decoding: line, as: UTF8.self),
                timestamp: .now,
                tokens: TokenCount(output: 1)
            )
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "notchlet-reader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func splitsLinesAcrossChunkBoundaries() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "big.jsonl")
        // Lines long enough that the 256 KiB chunks cut through them.
        let line = String(repeating: "x", count: 100_000)
        let lines = (0 ..< 10).map { "\($0)-\(line)" }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file)

        var seen: [String] = []
        let offset = try LineReader.forEachLine(in: file, from: 0) { seen.append(String(
            decoding: $0.prefix(2),
            as: UTF8.self
        )) }

        #expect(seen == (0 ..< 10).map { "\($0)-" })
        #expect(offset == UInt64(lines.joined(separator: "\n").utf8.count + 1))
    }

    @Test func leavesAPartialTrailingLineForTheNextRead() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "growing.jsonl")
        try Data("one\ntwo\nthr".utf8).write(to: file)

        var seen: [String] = []
        let offset = try LineReader.forEachLine(in: file, from: 0) { seen.append(String(decoding: $0, as: UTF8.self)) }
        #expect(seen == ["one", "two"])
        #expect(offset == 8)

        try Data("one\ntwo\nthree\n".utf8).write(to: file)
        let next = try LineReader
            .forEachLine(in: file, from: offset) { seen.append(String(decoding: $0, as: UTF8.self)) }
        #expect(seen == ["one", "two", "three"])
        #expect(next == 14)
    }

    @Test func rereadsOnlyWhatChanged() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stable = directory.appending(path: "a/stable.jsonl")
        let growing = directory.appending(path: "b/growing.jsonl")
        try FileManager.default.createDirectory(
            at: stable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: growing.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("s1\ns2\n".utf8).write(to: stable)
        try Data("g1\n".utf8).write(to: growing)
        let reader = LogDirectoryReader<LineCounter>(roots: [directory])

        let first = try await reader.events(since: nil)
        #expect(Set(first.map(\.model)) == ["s1", "s2", "g1"])

        // Append to one file; the parser state carries on from its offset.
        let handle = try FileHandle(forWritingTo: growing)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("g2\n".utf8))
        try handle.close()
        // Modification dates have second precision on some file systems.
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(5)],
            ofItemAtPath: growing.path
        )

        let second = try await reader.events(since: nil)
        #expect(Set(second.map(\.model)) == ["s1", "s2", "g1", "g2"])
        #expect(second.count == 4)

        // Rewritten shorter: read again from the start.
        try Data("g9\n".utf8).write(to: growing)
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(10)],
            ofItemAtPath: growing.path
        )
        let third = try await reader.events(since: nil)
        #expect(Set(third.map(\.model)) == ["s1", "s2", "g9"])
    }

    @Test func skipsFilesLastWrittenBeforeSince() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = directory.appending(path: "old.jsonl")
        let new = directory.appending(path: "new.jsonl")
        try Data("old\n".utf8).write(to: old)
        try Data("new\n".utf8).write(to: new)
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-7200)],
            ofItemAtPath: old.path
        )

        let reader = LogDirectoryReader<LineCounter>(roots: [directory])
        let events = try await reader.events(since: Date.now.addingTimeInterval(-3600))
        #expect(events.map(\.model) == ["new"])
    }
}
