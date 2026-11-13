import Foundation
@testable import Notchlet
import Testing

struct LogFilesTests {
    /// A date-filtered file under an earlier root is not a copy, so it must
    /// not shadow a newer same-named file in a later root.
    @Test func dateFilteredFileDoesNotShadowNewerFileInLaterRoot() throws {
        let older = try makeTemporaryDirectory()
        let newer = try makeTemporaryDirectory()
        let since = Date(timeIntervalSince1970: 1_000_000_000)

        try Data("old".utf8).write(to: older.appending(path: "session.log"))
        try FileManager.default.setAttributes(
            [.modificationDate: since.addingTimeInterval(-3600)],
            ofItemAtPath: older.appending(path: "session.log").path
        )
        try Data("new".utf8).write(to: newer.appending(path: "session.log"))
        try FileManager.default.setAttributes(
            [.modificationDate: since.addingTimeInterval(3600)],
            ofItemAtPath: newer.appending(path: "session.log").path
        )

        let files = LogFiles.list(under: [older, newer], withExtension: "log", modifiedSince: since)

        #expect(files.count == 1)
        #expect(files.first?.url == newer.appending(path: "session.log"))
    }

    /// A file that does qualify under an earlier root is still a copy and
    /// keeps shadowing the same name in a later root.
    @Test func qualifyingFileStillShadowsLaterRoot() throws {
        let first = try makeTemporaryDirectory()
        let second = try makeTemporaryDirectory()
        let since = Date(timeIntervalSince1970: 1_000_000_000)

        for root in [first, second] {
            try Data("x".utf8).write(to: root.appending(path: "session.log"))
            try FileManager.default.setAttributes(
                [.modificationDate: since.addingTimeInterval(3600)],
                ofItemAtPath: root.appending(path: "session.log").path
            )
        }

        let files = LogFiles.list(under: [first, second], withExtension: "log", modifiedSince: since)

        #expect(files.count == 1)
        #expect(files.first?.url == first.appending(path: "session.log"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
    }
}
