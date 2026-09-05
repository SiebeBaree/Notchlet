import Foundation
@testable import Notchlet
import Testing

/// The script the installer writes, run for real through `sh` and `nc`
/// against a listening socket: the one path a unit test on the parser
/// cannot vouch for.
@MainActor
struct HookSocketTests {
    @Test func scriptDeliversHeaderAndPayloadAndReturnsPromptly() async throws {
        // Short on purpose: socket paths are capped at 104 bytes.
        let home = URL(filePath: "/tmp/nl-\(UInt32.random(in: 0 ... 0xFFFF_FFFF))")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = AgentHookInstaller(home: home)
        installer.install([])
        let socket = HookSocket(path: installer.socketPath)
        defer { socket.stop() }

        // A script that dies before reading would turn the write below into
        // a SIGPIPE that takes the test host with it.
        signal(SIGPIPE, SIG_IGN)
        let received = AsyncStream<Data>.makeStream()
        try socket.start { data in received.continuation.yield(data) }

        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [installer.scriptURL.path, "claude-code"]
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin", "__CFBundleIdentifier": "com.t3tools.t3code"]
        let stdin = Pipe()
        process.standardInput = stdin
        try process.run()
        stdin.fileHandleForWriting.write(Data(#"{"session_id":"s1","hook_event_name":"Stop","cwd":"/tmp"}"#.utf8))
        try stdin.fileHandleForWriting.close()

        // Both waits have deadlines, so a broken socket or a stuck script
        // fails the test instead of hanging the run.
        let data = try #require(await Self.first(of: received.stream, within: .seconds(5)))
        let receivedAt = Date.now
        let message = try #require(AgentWaitRules.parse(data))
        #expect(message.provider == "claude-code")
        #expect(message.sessionID == "s1")
        #expect(message.bundleID == "com.t3tools.t3code")
        #expect(message.pid > 0)
        #expect(message.effect == .wait(.finished))

        let deadline = Date.now.addingTimeInterval(5)
        while process.isRunning, Date.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        if process.isRunning {
            process.terminate()
            Issue.record("The hook script did not exit")
        }
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        // `nc` returns once the listener closes, well inside its own 2s
        // idle timeout. Measured from receipt so a slow CI runner's process
        // spawn does not count against it.
        #expect(Date.now.timeIntervalSince(receivedAt) < 1.5)
    }

    /// The stream's first element, or nil once the deadline passes.
    private static func first(of stream: AsyncStream<Data>, within timeout: Duration) async -> Data? {
        await withTaskGroup(of: Data?.self) { group in
            group.addTask { await stream.first { _ in true } }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
