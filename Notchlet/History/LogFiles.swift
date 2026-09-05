import Foundation

/// A log file with the attributes the readers key on.
nonisolated struct LogFile: Sendable {
    let url: URL
    let size: UInt64
    let modified: Date
}

nonisolated enum LogFiles {
    /// Every regular file with the extension under the roots, minus files
    /// last written before `since`. Roots are in order of preference: a
    /// file name already seen under an earlier root is a copy (Codex
    /// archives a thread by moving it) and is skipped.
    static func list(under roots: [URL], withExtension ext: String, modifiedSince since: Date?) -> [LogFile] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        var files: [LogFile] = []
        var seenNames: Set<String> = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Array(keys), options: []
            ) else { continue }
            var names: Set<String> = []
            for case let url as URL in enumerator where url.pathExtension == ext {
                guard !seenNames.contains(url.lastPathComponent),
                      let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
                      let size = values.fileSize, let modified = values.contentModificationDate
                else { continue }
                names.insert(url.lastPathComponent)
                if let since, modified < since {
                    continue
                }
                files.append(LogFile(url: url, size: UInt64(size), modified: modified))
            }
            seenNames.formUnion(names)
        }
        return files
    }
}
