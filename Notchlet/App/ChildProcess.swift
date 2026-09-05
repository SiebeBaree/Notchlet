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
    /// the way Time Machine is. Throws only when the tool could not start.
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
            try await Task.detached {
                let process = child.process
                process.executableURL = executable
                process.arguments = arguments
                process.environment = environment
                process.currentDirectoryURL = currentDirectory
                let stdout = Pipe()
                process.standardOutput = stdout
                process.standardError = FileHandle.nullDevice
                let stdin = input.map { _ in Pipe() }
                process.standardInput = stdin ?? FileHandle.nullDevice
                try child.launch()
                if background {
                    setpriority(PRIO_DARWIN_PROCESS, id_t(process.processIdentifier), PRIO_DARWIN_BG)
                }
                if let stdin, let input {
                    // Fed to the end before stdout is read: every tool here
                    // writes only after reading all of its input. The
                    // throwing variant, so a child that exited early does
                    // not raise through the pipe.
                    try? stdin.fileHandleForWriting.write(contentsOf: input)
                    try? stdin.fileHandleForWriting.close()
                }
                let output = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return Exit(status: process.terminationStatus, output: output)
            }.value
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
