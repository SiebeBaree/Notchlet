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
        let started = Date.now
        try process.run()
        stdin.fileHandleForWriting.write(Data(#"{"session_id":"s1","hook_event_name":"Stop","cwd":"/tmp"}"#.utf8))
        try stdin.fileHandleForWriting.close()

        var iterator = received.stream.makeAsyncIterator()
        let data = try #require(await iterator.next())
        let message = try #require(AgentWaitRules.parse(data))
        #expect(message.provider == "claude-code")
        #expect(message.sessionID == "s1")
        #expect(message.bundleID == "com.t3tools.t3code")
        #expect(message.pid > 0)
        #expect(message.effect == .wait(.finished))

        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(Date.now.timeIntervalSince(started) < 2)
    }
}
