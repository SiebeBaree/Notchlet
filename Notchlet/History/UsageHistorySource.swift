import Foundation

/// Where one provider's past usage comes from: its logs on disk, or an
/// export from its dashboard.
nonisolated protocol UsageHistorySource: Sendable {
    /// Every request that may fall on or after `since`, in any order; nil
    /// asks for everything. Older events may come along, the ingestor
    /// ignores what it has sealed.
    func events(since: Date?) async throws -> [UsageEvent]
}

/// One line of a JSONL log, with a per-file state carried between lines.
nonisolated protocol LogLineParser: Sendable {
    associatedtype State: Sendable
    static var initialState: State { get }
    /// The raw bytes without the newline. Nil for a line without usage.
    static func parse(_ line: Data, state: inout State) -> UsageEvent?
}

/// A tree of JSONL logs read through one parser. Every file is remembered
/// by size and modification date with its events and parser state, so a
/// file that grew is read from where the last read stopped and one that
/// shrank from the start. Files older than `since` are skipped by their
/// modification date alone. At most four files parse at a time.
actor LogDirectoryReader<Parser: LogLineParser> {
    private struct Cached {
        var size: UInt64
        var modified: Date
        /// Just past the last complete line read.
        var offset: UInt64
        var state: Parser.State
        var events: [UsageEvent]
    }

    private nonisolated static var parallelism: Int { 4 }

    private let roots: [URL]
    private var cache: [String: Cached] = [:]

    init(roots: [URL]) {
        self.roots = roots
    }

    func events(since: Date?) async throws -> [UsageEvent] {
        let files = LogFiles.list(under: roots, withExtension: "jsonl", modifiedSince: since)
        var kept: [String: Cached] = [:]
        var jobs: [(url: URL, from: Cached)] = []
        for file in files {
            let cached = cache[file.url.path]
            if let cached, cached.size == file.size, cached.modified == file.modified {
                kept[file.url.path] = cached
                continue
            }
            var from = Cached(
                size: file.size, modified: file.modified, offset: 0, state: Parser.initialState, events: []
            )
            if let cached, file.size >= cached.offset {
                from.offset = cached.offset
                from.state = cached.state
                from.events = cached.events
            }
            jobs.append((file.url, from))
        }

        try await withThrowingTaskGroup(of: (String, Cached).self) { group in
            var pending = jobs[...]
            func startNext() {
                guard let job = pending.popFirst() else { return }
                group.addTask { try (job.url.path, Self.parse(job.url, from: job.from)) }
            }
            for _ in 0 ..< Self.parallelism {
                startNext()
            }
            for try await (path, cached) in group {
                kept[path] = cached
                try Task.checkCancellation()
                startNext()
            }
        }

        cache = kept
        return kept.values.flatMap(\.events)
    }

    private nonisolated static func parse(_ url: URL, from: Cached) throws -> Cached {
        var cached = from
        cached.offset = try LineReader.forEachLine(in: url, from: from.offset) { line in
            if let event = Parser.parse(line, state: &cached.state) {
                cached.events.append(event)
            }
        }
        return cached
    }
}

/// Streams a file line by line from a byte offset in 256 KiB reads. Hands
/// back the offset just past the last newline, so a partial trailing line
/// the CLI is still writing is left for the next read.
nonisolated enum LineReader {
    static let chunkSize = 256 * 1024

    @discardableResult
    static func forEachLine(in url: URL, from offset: UInt64, _ body: (Data) -> Void) throws -> UInt64 {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)

        var consumed = offset
        var buffer = Data()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            buffer.append(chunk)
            var lineStart = 0
            while let newline = buffer.indexOfNewline(from: lineStart) {
                body(buffer.subdata(in: lineStart ..< newline))
                lineStart = newline + 1
            }
            buffer.removeSubrange(0 ..< lineStart)
            consumed += UInt64(lineStart)
        }
        return consumed
    }
}

private nonisolated extension Data {
    /// `memchr` rather than `firstIndex(of:)`: this runs over every byte of
    /// every log, and the generic search is many times slower.
    func indexOfNewline(from start: Int) -> Int? {
        withUnsafeBytes { raw -> Int? in
            guard let base = raw.baseAddress, start < raw.count,
                  let found = memchr(base + start, Int32(UInt8(ascii: "\n")), raw.count - start)
            else { return nil }
            return UnsafeRawPointer(found) - base
        }
    }
}
