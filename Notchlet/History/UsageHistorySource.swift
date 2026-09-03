import Foundation

/// Where one provider's past usage comes from: the CLI's own logs on disk,
/// or an export from its dashboard. A provider that has one hands it out
/// through `UsageProvider.history`; the rest show live limits only.
nonisolated protocol UsageHistorySource: Sendable {
    /// Every request that may fall on or after `since`, in any order. Nil
    /// asks for everything the source has. Older events may come along
    /// (a log touched today can hold last week), the ingestor ignores
    /// what it has already sealed, so a source only has to be complete,
    /// not clever.
    func events(since: Date?) async throws -> [UsageEvent]
}

/// Reads one line of a JSONL log. Pure over the line and a per-file state,
/// which is what makes a parser testable against a handful of real lines.
/// A stateless parser uses an empty struct for its state.
nonisolated protocol LogLineParser: Sendable {
    associatedtype State: Sendable
    static var initialState: State { get }
    /// The event on this line, or nil for lines that carry no usage. The
    /// line is the raw bytes without the newline.
    static func parse(_ line: Data, state: inout State) -> UsageEvent?
}

/// A tree of JSONL logs read through one parser, kept for the app's
/// lifetime so a second read only touches what changed.
///
/// Every file is remembered by size and modification date with the events
/// it produced and the parser state at its end. A file that grew is read
/// from where the last read stopped; one that shrank is read again from the
/// start. Files older than `since` are skipped by their modification date
/// alone and dropped from memory. Files parse in parallel, at most four at
/// a time, so a first read of a year of logs uses the machine without
/// starving it.
actor LogDirectoryReader<Parser: LogLineParser> {
    private struct Cached {
        var size: UInt64
        var modified: Date
        /// Byte offset just past the last complete line read.
        var offset: UInt64
        var state: Parser.State
        var events: [UsageEvent]
    }

    private struct Job: Sendable {
        let url: URL
        let size: UInt64
        let modified: Date
        let offset: UInt64
        let state: Parser.State
        let events: [UsageEvent]
    }

    private nonisolated static var parallelism: Int { 4 }

    private let roots: [URL]
    private var cache: [String: Cached] = [:]

    init(roots: [URL]) {
        self.roots = roots
    }

    func events(since: Date?) async throws -> [UsageEvent] {
        let files = Self.logFiles(under: roots, modifiedSince: since)
        var kept: [String: Cached] = [:]
        var jobs: [Job] = []
        for file in files {
            if let cached = cache[file.url.path], cached.size == file.size, cached.modified == file.modified {
                kept[file.url.path] = cached
            } else if let cached = cache[file.url.path], file.size >= cached.offset {
                jobs.append(Job(
                    url: file.url, size: file.size, modified: file.modified,
                    offset: cached.offset, state: cached.state, events: cached.events
                ))
            } else {
                jobs.append(Job(
                    url: file.url, size: file.size, modified: file.modified,
                    offset: 0, state: Parser.initialState, events: []
                ))
            }
        }

        try await withThrowingTaskGroup(of: (String, Cached).self) { group in
            var pending = jobs[...]
            func startNext() {
                guard let job = pending.popFirst() else { return }
                group.addTask { try (job.url.path, Self.parse(job)) }
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

    /// Reads a file from the job's offset, continuing its parser state.
    private nonisolated static func parse(_ job: Job) throws -> Cached {
        var state = job.state
        var events = job.events
        let offset = try LineReader.forEachLine(in: job.url, from: job.offset) { line in
            if let event = Parser.parse(line, state: &state) {
                events.append(event)
            }
        }
        return Cached(size: job.size, modified: job.modified, offset: offset, state: state, events: events)
    }

    private struct LogFile {
        let url: URL
        let size: UInt64
        let modified: Date
    }

    /// Every `.jsonl` under the roots, with the attributes the cache keys
    /// on, minus files last written before `since`.
    private nonisolated static func logFiles(under roots: [URL], modifiedSince since: Date?) -> [LogFile] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        var files: [LogFile] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Array(keys), options: []
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
                      let size = values.fileSize, let modified = values.contentModificationDate
                else { continue }
                if let since, modified < since {
                    continue
                }
                files.append(LogFile(url: url, size: UInt64(size), modified: modified))
            }
        }
        return files
    }
}

/// Streams a file line by line from a byte offset, in 256 KiB reads, so a
/// transcript of any size costs one chunk of memory. Hands back the offset
/// just past the last newline: a partial trailing line, one the CLI is
/// still writing, is left for the next read.
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
