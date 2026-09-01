import Foundation

/// Shared plumbing for reading CLI credentials: JSON files in the home
/// directory, keychain items and JWT expiry claims. Providers compose these
/// instead of each rewriting them.
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
    /// gave us, while `security` keeps its access. Runs off the main actor
    /// so the child process never stalls the panel.
    static func keychainJSON<T: Decodable>(service: String) async -> T? {
        let data = await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", service, "-w"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil as Data? }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? data : nil
        }.value
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Expiry from a JWT's `exp` claim, without verifying the signature. We
    /// only decide whether a token is worth sending; the server does the
    /// real validation.
    static func jwtExpiry(of token: String) -> Date? {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return nil }
        var base64 = segments[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = payload["exp"] as? TimeInterval
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
