import Foundation
@testable import Notchlet
import Testing

struct DirectoryLockTests {
    private func temporaryLockURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "notchlet-lock-\(UUID().uuidString)")
    }

    @Test func acquireCreatesTheDirectoryAndReleaseRemovesIt() async {
        let url = temporaryLockURL()
        let lock = await DirectoryLock.acquire(url, stale: 60, attempts: 1, retryDelay: 0 ... 0)
        #expect(lock != nil)
        #expect(FileManager.default.fileExists(atPath: url.path))
        lock?.release()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aHeldLockStaysBusy() async {
        let url = temporaryLockURL()
        let first = await DirectoryLock.acquire(url, stale: 60, attempts: 1, retryDelay: 0 ... 0)
        defer { first?.release() }
        let second = await DirectoryLock.acquire(url, stale: 60, attempts: 2, retryDelay: 0.01 ... 0.02)
        #expect(second == nil)
    }

    @Test func aStaleLockIsTakenOver() async throws {
        let url = temporaryLockURL()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-120)],
            ofItemAtPath: url.path
        )
        let lock = await DirectoryLock.acquire(url, stale: 60, attempts: 1, retryDelay: 0 ... 0)
        #expect(lock != nil)
        lock?.release()
    }

    @Test func releaseLeavesASuccessorsLockAlone() async throws {
        let url = temporaryLockURL()
        let original = try #require(await DirectoryLock.acquire(url, stale: 60, attempts: 1, retryDelay: 0 ... 0))
        // The machine slept through the hold: the directory looks stale and
        // another process takes it over.
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-120)],
            ofItemAtPath: url.path
        )
        let successor = try #require(await DirectoryLock.acquire(url, stale: 60, attempts: 1, retryDelay: 0 ... 0))
        #expect(!original.isHeld)
        #expect(successor.isHeld)

        original.release()
        #expect(FileManager.default.fileExists(atPath: url.path))
        successor.release()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
