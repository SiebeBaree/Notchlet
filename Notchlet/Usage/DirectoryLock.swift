import Foundation

/// A lock directory in the style of Node's proper-lockfile, which Claude
/// Code uses around its token refresh and its keychain writes. `mkdir` is
/// atomic, so whoever creates the directory holds the lock; a directory
/// whose modification time is older than `stale` belongs to a holder that
/// died and can be taken over. Plain file system, so it coordinates with
/// Claude Code's processes and not just our own.
///
/// Holds here are seconds long against stale windows of 15s and 60s, so the
/// lock is never touched to keep it fresh. The one way a live hold can
/// still be taken over is the machine sleeping through it; the
/// modification time recorded at acquisition guards against releasing the
/// successor's lock in that case.
struct DirectoryLock: Sendable {
    let url: URL
    /// The directory's modification time as created by this holder. A
    /// successor that took the lock over recreated the directory, and its
    /// time differs.
    private let acquiredAt: Date?

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
                return DirectoryLock(url: url, acquiredAt: modificationDate(of: url))
            }
        }
        return nil
    }

    private static func tryAcquire(_ url: URL, stale: TimeInterval) -> Bool {
        if create(url) {
            return true
        }
        guard let modified = modificationDate(of: url), Date.now.timeIntervalSince(modified) > stale else {
            return false
        }
        try? FileManager.default.removeItem(at: url)
        return create(url)
    }

    private static func create(_ url: URL) -> Bool {
        (try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)) != nil
    }

    private static func modificationDate(of url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    /// Whether the directory is still the one this holder created.
    var isHeld: Bool {
        Self.modificationDate(of: url) == acquiredAt
    }

    /// Removes the directory, unless another process took the lock over in
    /// the meantime: then it is theirs to release.
    func release() {
        guard isHeld else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
