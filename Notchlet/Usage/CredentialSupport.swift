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

    /// The payload of a keychain generic password item, read through
    /// `/usr/bin/security` rather than the Security framework.
    ///
    /// CLIs write their items with that same tool, which puts it on the
    /// item's access list for good. Reading as Notchlet instead would show
    /// the keychain password prompt again after every token rotation: the
    /// CLI's rewrite of the item drops the "Always Allow" grant the user
    /// gave us, while `security` keeps its access. Notchlet's own items go
    /// through the same tool for the same reason.
    static func keychainData(service: String, account: String? = nil) async -> Data? {
        var arguments = ["find-generic-password", "-s", service]
        if let account {
            arguments += ["-a", account]
        }
        guard let output = await run("/usr/bin/security", arguments + ["-w"]) else { return nil }
        return decodeKeychainOutput(output)
    }

    static func keychainJSON<T: Decodable>(service: String) async -> T? {
        guard let data = await keychainData(service: service) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func keychainString(service: String, account: String) async -> String? {
        guard let data = await keychainData(service: service, account: account) else { return nil }
        let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// `security -w` prints the payload as text, or as `0x…` hex when it is
    /// not plain text. Either way this yields the stored bytes.
    static func decodeKeychainOutput(_ output: Data) -> Data {
        let text = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("0x") else { return Data(text.utf8) }
        let hex = text.dropFirst(2).prefix { $0.isHexDigit }
        return data(fromHex: String(hex))
    }

    /// Creates or replaces a generic password item. The command goes in on
    /// stdin with the value hex-encoded, the way Claude Code writes its own
    /// item, so nothing secret ever appears in an argument list. The names
    /// are quoted on that command line, so a name that could break the
    /// quoting is refused rather than escaped by guesswork; every name
    /// Notchlet uses is plain ASCII anyway.
    static func writeKeychainItem(service: String, account: String, value: Data) async -> Bool {
        guard isPlainKeychainName(service), isPlainKeychainName(account) else { return false }
        let hex = value.map { String(format: "%02x", $0) }.joined()
        let command = "add-generic-password -U -a \"\(account)\" -s \"\(service)\" -X \"\(hex)\"\n"
        return await run("/usr/bin/security", ["-i"], input: Data(command.utf8)) != nil
    }

    /// Whether a service or account name can go inside double quotes on a
    /// `security -i` command line unchanged.
    static func isPlainKeychainName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains { $0 == "\"" || $0 == "\\" || $0.isNewline }
    }

    /// Removes a generic password item. An item that is already gone counts
    /// as removed; anything else, a locked keychain say, does not.
    static func deleteKeychainItem(service: String, account: String) async -> Bool {
        let itemNotFound: Int32 = 44
        guard let status = await exitStatus(
            "/usr/bin/security", ["delete-generic-password", "-s", service, "-a", account]
        ) else { return false }
        return status == 0 || status == itemNotFound
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
        let path = FileManager.default.homeDirectoryForCurrentUser.appending(path: homePath)
        let sql = "SELECT hex(value) FROM \(table) WHERE key = '\(key)' LIMIT 1;"
        guard let output = await sqlite(path, sql: sql, options: ["-noheader"]) else { return nil }
        let hex = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(decoding: data(fromHex: hex).filter { $0 != 0 }, as: UTF8.self)
        return value.isEmpty ? nil : value
    }

    /// The rows of a read-only query as the JSON array `sqlite3 -json`
    /// prints, empty when the query matches nothing. Nil when the database
    /// could not be read at all. Same opening rules as `sqliteValue`.
    static func sqliteRows(path: URL, sql: String) async -> Data? {
        await sqlite(path, sql: sql, options: ["-json"])
    }

    private static func sqlite(_ path: URL, sql: String, options extra: [String]) async -> Data? {
        let options = ["-batch", "-readonly", "-cmd", ".timeout 1000"] + extra
        var output = await run("/usr/bin/sqlite3", options + [path.path, sql])
        if output == nil, !FileManager.default.fileExists(atPath: path.path + "-wal"),
           let encoded = path.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        {
            output = await run("/usr/bin/sqlite3", options + ["file:\(encoded)?immutable=1", sql])
        }
        return output
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
    /// cleanly.
    private static func run(_ tool: String, _ arguments: [String], input: Data? = nil) async -> Data? {
        guard let (status, output) = await launch(tool, arguments, input: input), status == 0 else { return nil }
        return output
    }

    private static func exitStatus(_ tool: String, _ arguments: [String]) async -> Int32? {
        await launch(tool, arguments, input: nil)?.status
    }

    /// Runs a system tool to completion, feeding it `input` on stdin when
    /// given. Runs off the main actor so the child process never stalls the
    /// panel. Nil only when the tool could not be started.
    private static func launch(
        _ tool: String,
        _ arguments: [String],
        input: Data?
    ) async -> (status: Int32, output: Data)? {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: tool)
            process.arguments = arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            let stdin = input.map { _ in Pipe() }
            process.standardInput = stdin ?? FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            if let stdin, let input {
                // The throwing variant: a child that exits before reading
                // would otherwise raise an ObjC exception through the pipe.
                try? stdin.fileHandleForWriting.write(contentsOf: input)
                try? stdin.fileHandleForWriting.close()
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, data)
        }.value
    }

    /// Expiry from a JWT's `exp` claim, without verifying the signature. We
    /// only decide whether a token is worth sending; the server does the
    /// real validation.
    nonisolated static func jwtExpiry(of token: String) -> Date? {
        guard let exp = jwtClaims(of: token)?["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// The decoded payload of a JWT, unverified.
    nonisolated static func jwtClaims(of token: String) -> [String: Any]? {
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
