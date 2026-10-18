import CommonCrypto
import Foundation

/// The OAuth token Claude Desktop mints for its Code tab and hands to the
/// Claude Code it bundles, so a Mac with only the app signed in still has
/// one. Desktop keeps it in its own token cache, `oauth:tokenCacheV2` in
/// its `config.json`, sealed with Electron's safeStorage: AES-128-CBC under
/// a key derived from the "Claude Safe Storage" keychain item, the scheme
/// Chromium uses for cookies. Never refreshed here: Desktop rotates the
/// token itself and OAuth rejects a reused refresh token, so a refresh from
/// Notchlet would sign the Code tab out.
enum ClaudeDesktopTokenCache {
    struct Token: Equatable, Sendable {
        let accessToken: String
        let expiresAt: Date
    }

    static let configPath = "Library/Application Support/Claude/config.json"
    static let keychainService = "Claude Safe Storage"
    static let keychainAccount = "Claude Key"

    static var isPresent: Bool {
        CredentialSupport.homePathExists(configPath)
    }

    /// The encrypted payload can change without the storage key changing.
    private static func sealedCache() -> Data? {
        struct Config: Decodable {
            var cache: String?

            enum CodingKeys: String, CodingKey {
                case cache = "oauth:tokenCacheV2"
            }
        }
        guard let config: Config = CredentialSupport.homeJSON(configPath),
              let encoded = config.cache else { return nil }
        return Data(base64Encoded: encoded)
    }

    /// Session-only: never copy Desktop's storage key to disk or alter its
    /// Keychain permissions. A failed read waits for an explicit retry.
    @MainActor
    final class Reader {
        private let readCache: () -> Data?
        private let readPassword: () async -> String?
        private var password: String?
        private var pendingPassword: Task<String?, Never>?
        private var accessBlocked = false
        private var lastSealed: Data?
        private var lastToken: Token?

        init(
            readCache: @escaping () -> Data? = { ClaudeDesktopTokenCache.sealedCache() },
            readPassword: @escaping () async -> String? = {
                await CredentialSupport.keychainString(service: keychainService, account: keychainAccount)
            }
        ) {
            self.readCache = readCache
            self.readPassword = readPassword
        }

        func retryAccess() {
            guard pendingPassword == nil else { return }
            if accessBlocked {
                password = nil
                accessBlocked = false
                lastSealed = nil
                lastToken = nil
            }
        }

        func read() async throws -> Token? {
            guard !accessBlocked else { throw ProviderError.notAvailable(.keychainAccess) }
            guard let sealed = readCache() else { return nil }
            if sealed == lastSealed {
                return lastToken
            }
            if password == nil {
                // Refresh rescheduling must not cancel a permission dialog or
                // launch another read while the user is answering the first.
                if pendingPassword == nil {
                    pendingPassword = Task {
                        let value = await readPassword()
                        password = value
                        accessBlocked = value == nil
                        pendingPassword = nil
                        return value
                    }
                }
                _ = await pendingPassword?.value
            }
            guard let password,
                  let json = decrypt(sealed, password: password),
                  (try? JSONSerialization.jsonObject(with: json)) is [String: Any]
            else {
                accessBlocked = true
                throw ProviderError.notAvailable(.keychainAccess)
            }
            lastSealed = sealed
            lastToken = token(in: json)
            return lastToken
        }
    }

    /// Electron safeStorage on macOS: a `v10` prefix, then AES-128-CBC with
    /// PKCS#7 padding, the key being PBKDF2-SHA1 of the keychain password
    /// with the fixed salt and iteration count Chromium uses, and the IV
    /// sixteen spaces.
    nonisolated static func decrypt(_ sealed: Data, password: String) -> Data? {
        let prefix = Data("v10".utf8)
        guard sealed.starts(with: prefix) else { return nil }
        let ciphertext = sealed.dropFirst(prefix.count)
        guard !ciphertext.isEmpty, ciphertext.count % kCCBlockSizeAES128 == 0 else { return nil }

        var key = [UInt8](repeating: 0, count: kCCKeySizeAES128)
        let salt = Array("saltysalt".utf8)
        let derived = Array(password.utf8).withUnsafeBufferPointer { passwordBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordBytes.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
                passwordBytes.count,
                salt, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                &key, key.count
            )
        }
        guard derived == kCCSuccess else { return nil }

        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        var plaintext = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        var written = 0
        let status = Array(ciphertext).withUnsafeBufferPointer { input in
            CCCrypt(
                CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                key, key.count, iv,
                input.baseAddress, input.count,
                &plaintext, plaintext.count, &written
            )
        }
        guard status == kCCSuccess else { return nil }
        return Data(plaintext.prefix(written))
    }

    /// The cache is a map from `acct:<account>|<client>:<org>:<host>:<scope>`
    /// to an entry with `token` and `expiresAt` in milliseconds, or null
    /// where a refresh was rejected. Only entries issued to Claude Code's
    /// client are usable; the Code tab's own, with the sessions scope, is
    /// the one Desktop keeps rotating, so it wins over a longer-lived
    /// sibling that may have been minted once and forgotten.
    nonisolated static func token(in json: Data, clientID: String = ClaudeTokenRefresh.clientID) -> Token? {
        guard let cache = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        let codeTabScope = "user:sessions:claude_code"
        return cache.compactMap { key, value -> (codeTab: Bool, token: Token)? in
            let identity = key.split(separator: "|", maxSplits: 1).last.map(String.init) ?? key
            guard identity.hasPrefix("\(clientID):"),
                  let entry = value as? [String: Any],
                  let accessToken = entry["token"] as? String, !accessToken.isEmpty,
                  let expiresAt = entry["expiresAt"] as? Double
            else { return nil }
            let token = Token(accessToken: accessToken, expiresAt: Date(timeIntervalSince1970: expiresAt / 1000))
            return (identity.hasSuffix(codeTabScope), token)
        }
        .max { lhs, rhs in
            lhs.codeTab != rhs.codeTab ? rhs.codeTab : lhs.token.expiresAt < rhs.token.expiresAt
        }?.token
    }
}
