import Foundation

/// Reading CLI credentials: home directory files, keychain items, Electron
/// state databases and JWT claims.
enum CredentialSupport {
    /// Paths are relative to the home directory. Providers use this to tell
    /// whether their CLI is installed.
    static func homePathExists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: homeURL(relativePath).path)
    }

    static func homeJSON<T: Decodable>(_ relativePath: String) -> T? {
        guard let data = try? Data(contentsOf: homeURL(relativePath)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func homeURL(_ relativePath: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: relativePath)
    }

    /// Read through `/usr/bin/security` rather than the Security framework:
    /// CLIs write their items with that tool, which keeps it on the access
    /// list, whereas a read as Notchlet prompts for the keychain password
    /// again after every token rotation. Notchlet's own items go through it
    /// for the same reason.
    static func keychainData(service: String, account: String? = nil) async -> Data? {
        var arguments = ["find-generic-password", "-s", service]
        if let account {
            arguments += ["-a", account]
        }
        guard let output = await run(security, arguments + ["-w"]) else { return nil }
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

    /// The command goes in on stdin with the value hex-encoded, the way
    /// Claude Code writes its own item, so nothing secret appears in an
    /// argument list. A name that could break the quoting is refused rather
    /// than escaped by guesswork.
    static func writeKeychainItem(service: String, account: String, value: Data) async -> Bool {
        guard isPlainKeychainName(service), isPlainKeychainName(account) else { return false }
        let hex = value.map { String(format: "%02x", $0) }.joined()
        let command = "add-generic-password -U -a \"\(account)\" -s \"\(service)\" -X \"\(hex)\"\n"
        return await run(security, ["-i"], input: Data(command.utf8)) != nil
    }

    static func isPlainKeychainName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains { $0 == "\"" || $0 == "\\" || $0.isNewline }
    }

    /// An item that is already gone counts as removed; a locked keychain
    /// does not.
    static func deleteKeychainItem(service: String, account: String) async -> Bool {
        let itemNotFound: Int32 = 44
        guard let exit = try? await ChildProcess.run(
            security,
            ["delete-generic-password", "-s", service, "-a", account]
        )
        else { return false }
        return exit.status == 0 || exit.status == itemNotFound
    }

    /// One value from an Electron app's key-value state table, through
    /// `/usr/bin/sqlite3` read-only so the app's database is never touched.
    ///
    /// With the app closed, a WAL-mode database has no `-shm` sidecar and a
    /// read-only connection cannot create one, so SQLite refuses to open
    /// it; the retry with `immutable=1` skips locking, which is safe exactly
    /// when no `-wal` file exists. The value comes back as hex because the
    /// shell truncates the UTF-16 blobs these stores sometimes hold at the
    /// first NUL; dropping the NULs recovers the ASCII token either way.
    static func sqliteValue(homePath: String, table: String, key: String) async -> String? {
        guard homePathExists(homePath) else { return nil }
        let path = homeURL(homePath)
        let sql = "SELECT hex(value) FROM \(table) WHERE key = '\(key)' LIMIT 1;"
        guard let output = await sqlite(path, sql: sql, options: ["-noheader"]) else { return nil }
        let hex = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(decoding: data(fromHex: hex).filter { $0 != 0 }, as: UTF8.self)
        return value.isEmpty ? nil : value
    }

    /// The JSON array `sqlite3 -json` prints, empty when nothing matches,
    /// nil when the database could not be read. Same opening rules as
    /// `sqliteValue`.
    static func sqliteRows(path: URL, sql: String) async -> Data? {
        await sqlite(path, sql: sql, options: ["-json"])
    }

    private static func sqlite(_ path: URL, sql: String, options extra: [String]) async -> Data? {
        let options = ["-batch", "-readonly", "-cmd", ".timeout 1000"] + extra
        var output = await run(sqlite3, options + [path.path, sql])
        if output == nil, !FileManager.default.fileExists(atPath: path.path + "-wal"),
           let encoded = path.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        {
            output = await run(sqlite3, options + ["file:\(encoded)?immutable=1", sql])
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

    private static let security = URL(filePath: "/usr/bin/security")
    private static let sqlite3 = URL(filePath: "/usr/bin/sqlite3")

    /// The tool's standard output when it exits cleanly.
    private static func run(_ tool: URL, _ arguments: [String], input: Data? = nil) async -> Data? {
        guard let exit = try? await ChildProcess.run(tool, arguments, input: input),
              exit.status == 0 else { return nil }
        return exit.output
    }

    /// Unverified: the server does the real validation.
    nonisolated static func jwtExpiry(of token: String) -> Date? {
        guard let exp = jwtClaims(of: token)?["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

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
