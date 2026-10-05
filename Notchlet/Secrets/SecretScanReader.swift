import CryptoKit
import Foundation

/// Only file metadata and hashes are persisted. The preceding complete
/// record is replayed so a batch boundary retains the scanner's context.
nonisolated struct SecretFileCheckpoint: Codable, Equatable, Sendable {
    var identity: String
    var size: UInt64
    var modified: Date
    var offset: UInt64
    var line: Int
    var contextOffset: UInt64
    var contextLine: Int
    var prefixHash: String
    var tailHash: String
}

nonisolated struct SecretScanBatch: Sendable {
    struct Portion: Sendable {
        let url: URL
        let lines: Range<Int>
        let firstLine: Int
        let checkpoint: SecretFileCheckpoint
    }

    var data = Data()
    var portions: [Portion] = []

    func locate(_ matches: [SecretMatch]) -> [SecretMatch] {
        matches.compactMap { match in
            guard let portion = portions.first(where: { $0.lines.contains(match.line) }) else { return nil }
            var match = match
            match.file = portion.url
            match.line = portion.firstLine + match.line - portion.lines.lowerBound
            return match
        }
    }
}

/// Bounds normal batches by bytes, not path count. A single JSON record
/// stays intact even when larger than the target; keys may occur anywhere
/// inside tool results. Partial trailing records wait for the next pass.
actor SecretScanReader {
    private let urls: [URL]
    private let targetBytes: Int
    private var checkpoints: [String: SecretFileCheckpoint]
    private var index = 0
    private var current: RecordReader?

    init(urls: [URL], checkpoints: [String: SecretFileCheckpoint], targetBytes: Int = 4 * 1024 * 1024) {
        self.urls = urls
        self.checkpoints = checkpoints
        self.targetBytes = max(1, targetBytes)
    }

    func next() throws -> SecretScanBatch? {
        var batch = SecretScanBatch()
        var lineCount = 0
        while index < urls.count, batch.data.count < targetBytes, batch.portions.count < 256 {
            try Task.checkCancellation()
            let url = urls[index]
            if current == nil {
                do {
                    current = try RecordReader(url: url, checkpoint: checkpoints[url.path])
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                    index += 1
                    continue
                }
            }
            guard let reader = current else { break }
            if let part = try reader.read(targetBytes: targetBytes - batch.data.count) {
                batch.data.append(part.data)
                batch.portions.append(.init(
                    url: url, lines: (lineCount + 1) ..< (lineCount + part.lines + 1),
                    firstLine: part.firstLine, checkpoint: part.checkpoint
                ))
                lineCount += part.lines
                checkpoints[url.path] = part.checkpoint
            } else {
                current = nil
                index += 1
            }
        }
        return batch.portions.isEmpty ? nil : batch
    }

    private final class RecordReader {
        struct Part {
            let data: Data
            let lines: Int
            let firstLine: Int
            let checkpoint: SecretFileCheckpoint
        }

        let handle: FileHandle
        let identity: String
        let size: UInt64
        let modified: Date
        var offset: UInt64 = 0
        var committedOffset: UInt64 = 0
        var line = 0
        var context = Data()
        var contextOffset: UInt64 = 0
        var contextLine = 0
        var finished = false

        init(url: URL, checkpoint: SecretFileCheckpoint?) throws {
            handle = try FileHandle(forReadingFrom: url)
            let values = try handle.fileMetadata()
            identity = values.identity
            size = values.size
            modified = values.modified
            if let checkpoint, checkpoint.identity == identity, size >= checkpoint.size {
                if size == checkpoint.size, modified == checkpoint.modified, checkpoint.offset == size {
                    finished = true
                } else if size > checkpoint.size || modified == checkpoint.modified,
                          try fingerprint(at: 0, count: min(4096, checkpoint.offset)) == checkpoint.prefixHash,
                          try fingerprint(at: checkpoint.offset - min(4096, checkpoint.offset),
                                          count: min(4096, checkpoint.offset)) == checkpoint.tailHash
                {
                    offset = checkpoint.contextOffset
                    committedOffset = checkpoint.offset
                    line = checkpoint.contextLine
                }
            }
        }

        deinit { try? handle.close() }

        func read(targetBytes: Int) throws -> Part? {
            guard !finished else { return nil }
            try handle.seek(toOffset: offset)
            let firstLine = context.isEmpty ? line + 1 : contextLine + 1
            var output = context
            var lines = context.isEmpty ? 0 : 1
            var buffer = Data()
            var searchedUntil = 0
            var position = offset
            let previousOffset = committedOffset

            while position < size {
                try Task.checkCancellation()
                let chunk = try handle
                    .read(upToCount: Int(min(UInt64(LineReader.chunkSize), size - position))) ?? Data()
                guard !chunk.isEmpty else { break }
                position += UInt64(chunk.count)
                buffer.append(chunk)
                guard buffer.count <= 256 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                var start = 0
                while let newline = buffer.indexOfNewline(from: searchedUntil) {
                    try Task.checkCancellation()
                    let record = buffer.subdata(in: start ..< (newline + 1))
                    contextOffset = offset
                    contextLine = line
                    context = record
                    offset += UInt64(record.count)
                    line += 1
                    output.append(record)
                    guard output.count <= 256 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                    lines += 1
                    start = newline + 1
                    searchedUntil = start
                    if offset > previousOffset, output.count >= targetBytes {
                        break
                    }
                }
                searchedUntil = buffer.count - start
                buffer.removeSubrange(0 ..< start)
                if offset > previousOffset, output.count >= targetBytes {
                    break
                }
            }
            guard offset > previousOffset else {
                finished = true
                return nil
            }
            let checkpoint = try SecretFileCheckpoint(
                identity: identity, size: size, modified: modified, offset: offset, line: line,
                contextOffset: contextOffset, contextLine: contextLine,
                prefixHash: fingerprint(at: 0, count: min(4096, offset)),
                tailHash: fingerprint(at: offset - min(4096, offset), count: min(4096, offset))
            )
            committedOffset = offset
            return Part(data: output, lines: lines, firstLine: firstLine, checkpoint: checkpoint)
        }

        private func fingerprint(at offset: UInt64, count: UInt64) throws -> String {
            try handle.seek(toOffset: offset)
            let data = try handle.read(upToCount: Int(count)) ?? Data()
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }
}

private nonisolated extension FileHandle {
    func fileMetadata() throws -> (identity: String, size: UInt64, modified: Date) {
        var value = stat()
        guard fstat(fileDescriptor, &value) == 0 else { throw POSIXError(.EIO) }
        return (
            "\(value.st_dev):\(value.st_ino):\(value.st_birthtimespec.tv_sec):\(value.st_birthtimespec.tv_nsec)",
            UInt64(max(0, value.st_size)),
            Date(timeIntervalSince1970: Double(value.st_mtimespec.tv_sec) + Double(value.st_mtimespec.tv_nsec) / 1e9)
        )
    }
}
