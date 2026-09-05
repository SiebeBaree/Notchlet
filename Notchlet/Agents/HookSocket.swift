import Darwin
import Foundation

/// The Unix socket the hook script writes to, one message per connection.
/// The script pipes through `nc`, which only returns once this side closes,
/// so the read stops as soon as the message parses (or the peer goes quiet
/// for a moment) rather than waiting for an EOF `nc` never sends. Accepting
/// happens on a dispatch source; each read on its own background block, so
/// a slow client never blocks the next one and the main thread only ever
/// sees the finished bytes.
///
/// `nonisolated` opts out of the project's main-actor default: the accept
/// and read closures run on dispatch queues, and a main-actor closure
/// invoked there traps.
final nonisolated class HookSocket {
    /// A dot folder rather than Application Support: four CLIs run the hook
    /// command through four different quoting paths, and a path without
    /// spaces has nothing to quote. It also stays well under the 104 byte
    /// limit on socket paths.
    static let defaultPath = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".notchlet/hook.sock").path

    private static let maxMessageBytes = 64 * 1024
    private static let queue = DispatchQueue(label: "be.baree.Notchlet.hooks")

    let path: String
    private var source: DispatchSourceRead?
    private var fd: Int32 = -1

    init(path: String = HookSocket.defaultPath) {
        self.path = path
    }

    struct SocketError: Error {
        let step: String
        let code: Int32
    }

    func start(handler: @escaping @MainActor @Sendable (Data) -> Void) throws {
        guard source == nil else { return }
        try FileManager.default.createDirectory(
            at: URL(filePath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError(step: "socket", code: errno) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { throw SocketError(step: "path", code: ENAMETOOLONG) }
        withUnsafeMutablePointer(to: &address.sun_path) { sunPath in
            sunPath.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                _ = strncpy(destination, path, capacity - 1)
            }
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            close(fd)
            throw SocketError(step: "bind", code: errno)
        }
        guard listen(fd, 8) == 0 else {
            close(fd)
            throw SocketError(step: "listen", code: errno)
        }
        chmod(path, 0o600)
        self.fd = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: Self.queue)
        source.setEventHandler {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            DispatchQueue.global(qos: .utility).async {
                let data = Self.readMessage(from: client)
                close(client)
                guard !data.isEmpty else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        handler(data)
                    }
                }
            }
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        if fd >= 0 {
            close(fd)
            fd = -1
        }
        unlink(path)
    }

    /// Reads until the message parses, the peer closes, 300ms pass with
    /// nothing new, or the cap is hit.
    private static func readMessage(from client: Int32) -> Data {
        var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while data.count < maxMessageBytes {
            let count = read(client, &chunk, chunk.count)
            guard count > 0 else { break }
            data.append(chunk, count: count)
            if isComplete(data) {
                break
            }
        }
        return data
    }

    /// A header line followed by JSON that parses as a whole.
    private static func isComplete(_ data: Data) -> Bool {
        guard let newline = data.firstIndex(of: UInt8(ascii: "\n")) else { return false }
        let body = data[data.index(after: newline)...]
        return (try? JSONSerialization.jsonObject(with: body)) != nil
    }
}
