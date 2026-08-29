import Foundation
import Security

/// Shared plumbing for reading CLI credentials: JSON files in the home
/// directory, keychain items and JWT expiry claims. Providers compose these
/// instead of each rewriting them.
enum CredentialSupport {
    /// Decodes a JSON file at a path relative to the user's home directory.
    static func homeJSON<T: Decodable>(_ relativePath: String) -> T? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: relativePath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Decodes the JSON payload of a keychain generic password item. Reading
    /// another app's item triggers a one-time macOS permission prompt.
    static func keychainJSON<T: Decodable>(service: String) -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
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
