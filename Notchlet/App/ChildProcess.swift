import Foundation

/// Runs a command-line tool to completion off the main actor, so a child
/// process never stalls the panel. Cancelling the task terminates the child.
nonisolated enum ChildProcess {
    struct Exit: Sendable {
        let status: Int32
        let output: Data
    }

    /// `input` goes to stdin. `background` moves the child to the
    /// background tier, what `taskpolicy -b` does: CPU and I/O throttled
    /// the way Time Machine is. Throws on launch or I/O failure and cancellation.
    static func run(
        _ executable: URL,
        _ arguments: [String],
        input: Data? = nil,
        background: Bool = false,
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil
    ) async throws -> Exit {
        let child = Child()
        return try await withTaskCancellationHandler {
            let result = await Task.detached {
                let process = child.process
                process.executableURL = executable
                process.arguments = arguments
                process.environment = environment
                process.currentDirectoryURL = currentDirectory
                let stdout = Pipe()
                process.standardOutput = stdout
                process.standardError = FileHandle.nullDevice
                let stdin = input.map { _ in Pipe() }
                defer { try? stdin?.fileHandleForWriting.close() }
                if let stdin {
                    // A helper can exit during a write, including when cancelled.
                    // Without this, SIGPIPE terminates the app before Swift can throw.
                    guard fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                }
                process.standardInput = stdin ?? FileHandle.nullDevice
                try child.launch()
                if background {
                    setpriority(PRIO_DARWIN_PROCESS, id_t(process.processIdentifier), PRIO_DARWIN_BG)
                }
                let output: Data
                do {
                    if let stdin, let input {
                        // Every tool here reads all its input before writing output.
                        try stdin.fileHandleForWriting.write(contentsOf: input)
                        try stdin.fileHandleForWriting.close()
                    }
                    output = try stdout.fileHandleForReading.readToEnd() ?? Data()
                } catch {
                    child.cancel()
                    process.waitUntilExit()
                    throw error
                }
                process.waitUntilExit()
                return Exit(status: process.terminationStatus, output: output)
            }.result
            // Cancellation can break a pending write with EPIPE. Callers need
            // to distinguish their own cancellation from a helper failure.
            try Task.checkCancellation()
            return try result.get()
        } onCancel: {
            child.cancel()
        }
    }

    /// `Process` is not Sendable; this carries one across the task
    /// boundary so cancellation can still reach it. The lock orders
    /// launch against cancel: `terminate()` on a process that never
    /// launched raises, and a cancel that lands first must keep the
    /// detached task from launching at all.
    private final class Child: @unchecked Sendable {
        let process = Process()
        private let lock = NSLock()
        private var launched = false
        private var cancelled = false

        func launch() throws {
            try lock.withLock {
                if cancelled {
                    throw CancellationError()
                }
                try process.run()
                launched = true
            }
        }

        func cancel() {
            lock.withLock {
                cancelled = true
                if launched {
                    process.terminate()
                }
            }
        }
    }
}
