import Darwin
import Foundation
@testable import Notchlet
import Testing

nonisolated struct ChildProcessTests {
    @Test func sendsInputAndCollectsOutput() async throws {
        let input = Data("hello from Notchlet\n".utf8)
        let result = try await ChildProcess.run(URL(filePath: "/bin/cat"), [], input: input)
        #expect(result.status == 0)
        #expect(result.output == input)
    }

    @Test func preservesNonzeroExitStatus() async throws {
        let result = try await ChildProcess.run(URL(filePath: "/bin/sh"), ["-c", "exit 7"])
        #expect(result.status == 7)
    }

    @Test func earlyExitDuringInputThrowsWithoutTerminatingTheApp() async {
        await #expect(processExitsWith: .success) {
            // The hook test ignores SIGPIPE globally. Only this isolated
            // process can restore it without changing other running tests.
            signal(SIGPIPE, SIG_DFL)
            alarm(10)
            defer { alarm(0) }

            await #expect(throws: (any Error).self) {
                try await ChildProcess.run(
                    URL(filePath: "/usr/bin/true"), [],
                    input: Data(repeating: 65, count: 1024 * 1024)
                )
            }
        }
    }

    @Test func cancellingDuringInputThrowsWithoutTerminatingTheApp() async {
        await #expect(processExitsWith: .success) {
            signal(SIGPIPE, SIG_DFL)
            alarm(15)
            defer { alarm(0) }

            let directory = FileManager.default.temporaryDirectory.appending(path: "notchlet-child-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let ready = directory.appending(path: "ready")
            let task = Task {
                try await ChildProcess.run(
                    URL(filePath: "/bin/sh"),
                    ["-c", ": > \"$1\"; exec /bin/sleep 10", "notchlet-test", ready.path],
                    input: Data(repeating: 65, count: 1024 * 1024)
                )
            }
            defer { task.cancel() }

            // Wait for the helper to launch before cancelling. Its unread
            // input is larger than the pipe can buffer.
            let deadline = Date.now.addingTimeInterval(5)
            while !FileManager.default.fileExists(atPath: ready.path), Date.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(FileManager.default.fileExists(atPath: ready.path))
            task.cancel()
            await #expect(throws: CancellationError.self) {
                try await task.value
            }
        }
    }
}
