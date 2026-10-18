import Foundation

/// A lock directory in the style of Node's proper-lockfile, which Claude
/// Code uses around its token refresh and its keychain writes: `mkdir` is
/// atomic, so whoever creates the directory holds the lock, and one older
/// than `stale` belongs to a holder that died. Holds here are seconds long
/// against stale windows of 15s and 60s, so the lock is never touched to
/// keep it fresh; the modification time recorded at acquisition stops a
/// hold the machine slept through from releasing its successor's lock.
struct DirectoryLock: Sendable {
    let url: URL
    /// A successor that took the lock over recreated the directory, and its
    /// time differs.
    private let acquiredAt: Date?

    /// The same retry rhythm Claude Code uses. Nil when the lock stayed
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

    var isHeld: Bool {
        Self.modificationDate(of: url) == acquiredAt
    }

    /// A lock another process took over is theirs to release.
    func release() {
        guard isHeld else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
