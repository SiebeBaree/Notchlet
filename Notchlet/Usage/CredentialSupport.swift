import Foundation

/// Shared plumbing for reading CLI credentials: JSON files in the home
/// directory, keychain items, Electron state databases and JWT claims.
/// Providers compose these instead of each rewriting them.
enum CredentialSupport {
    /// Whether a path relative to the home directory exists. Providers use
    /// this to tell if their CLI is installed at all (its state directory
    /// exists), independent of whether the login is still valid.
    static func homePathExists(_ relativePath: String) -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: relativePath)
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Decodes a JSON file at a path relative to the user's home directory.
    static func homeJSON<T: Decodable>(_ relativePath: String) -> T? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: relativePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Decodes the JSON payload of a keychain generic password item, read
    /// through `/usr/bin/security` rather than the Security framework.
    ///
    /// CLIs write their items with that same tool, which puts it on the
    /// item's access list for good. Reading as Notchlet instead would show
    /// the keychain password prompt again after every token rotation: the
    /// CLI's rewrite of the item drops the "Always Allow" grant the user
    /// gave us, while `security` keeps its access.
    static func keychainJSON<T: Decodable>(service: String) async -> T? {
        guard let data = await run("/usr/bin/security", ["find-generic-password", "-s", service, "-w"])
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// One value from the key-value table of a SQLite database at a path
    /// relative to the home directory, read through `/usr/bin/sqlite3`.
    /// Electron apps (Cursor, VS Code) keep their login state in such a
    /// table.
    ///
    /// Opened read-only with a short busy timeout, so a write by the running
    /// app never fails the read and the app's database is never touched.
    /// With the app closed, a WAL-mode database has no `-shm` sidecar and a
    /// read-only connection cannot create one, so SQLite refuses to open it;
    /// the retry with `immutable=1` skips locking, which is safe exactly
    /// when no `-wal` file exists (otherwise unwritten rows would be
    /// missed). The value comes back as hex because the shell truncates the
    /// UTF-16 blobs these stores sometimes hold at the first NUL byte;
    /// dropping the NULs recovers the ASCII token either way.
    static func sqliteValue(homePath: String, table: String, key: String) async -> String? {
        guard homePathExists(homePath) else { return nil }
        let path = FileManager.default.homeDirectoryForCurrentUser.appending(path: homePath).path
        let sql = "SELECT hex(value) FROM \(table) WHERE key = '\(key)' LIMIT 1;"
        let options = ["-batch", "-noheader", "-readonly", "-cmd", ".timeout 1000"]
        var output = await run("/usr/bin/sqlite3", options + [path, sql])
        if output == nil, !FileManager.default.fileExists(atPath: path + "-wal"),
           let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        {
            output = await run("/usr/bin/sqlite3", options + ["file:\(encoded)?immutable=1", sql])
        }
        guard let output else { return nil }
        let hex = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(decoding: data(fromHex: hex).filter { $0 != 0 }, as: UTF8.self)
        return value.isEmpty ? nil : value
    }

    /// Bytes from a hex string as `hex()` prints it; empty when malformed.
    static func data(fromHex hex: String) -> Data {
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) {
            guard let byte = UInt8(hex[index ..< next], radix: 16) else { return Data() }
            data.append(byte)
            index = next
        }
        return data
    }

    /// Runs a system tool and returns its standard output when it exits
    /// cleanly. Runs off the main actor so the child process never stalls
    /// the panel.
    private static func run(_ tool: String, _ arguments: [String]) async -> Data? {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: tool)
            process.arguments = arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil as Data? }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? data : nil
        }.value
    }

    /// Expiry from a JWT's `exp` claim, without verifying the signature. We
    /// only decide whether a token is worth sending; the server does the
    /// real validation.
    static func jwtExpiry(of token: String) -> Date? {
        guard let exp = jwtClaims(of: token)?["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// The decoded payload of a JWT, unverified.
    static func jwtClaims(of token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return nil }
        var base64 = segments[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
