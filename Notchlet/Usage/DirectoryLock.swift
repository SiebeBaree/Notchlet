import Foundation

/// A lock directory in the style of Node's proper-lockfile, which Claude
/// Code uses around its token refresh and its keychain writes. `mkdir` is
/// atomic, so whoever creates the directory holds the lock; a directory
/// whose modification time is older than `stale` belongs to a holder that
/// died and can be taken over. Plain file system, so it coordinates with
/// Claude Code's processes and not just our own.
struct DirectoryLock: Sendable {
    let url: URL

    /// Tries up to `attempts` times, sleeping a random `retryDelay` between
    /// tries, the same rhythm Claude Code uses. Nil when the lock stayed
    /// busy.
    static func acquire(
        _ url: URL,
        stale: TimeInterval,
        attempts: Int,
        retryDelay: ClosedRange<TimeInterval>
    ) async -> DirectoryLock? {
        for attempt in 0 ..< attempts {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(Double.random(in: retryDelay)))
            }
            if tryAcquire(url, stale: stale) {
                return DirectoryLock(url: url)
            }
        }
        return nil
    }

    private static func tryAcquire(_ url: URL, stale: TimeInterval) -> Bool {
        if create(url) {
            return true
        }
        guard let modified = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date,
              Date.now.timeIntervalSince(modified) > stale
        else {
            return false
        }
        try? FileManager.default.removeItem(at: url)
        return create(url)
    }

    private static func create(_ url: URL) -> Bool {
        (try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)) != nil
    }

    func release() {
        try? FileManager.default.removeItem(at: url)
    }
}
