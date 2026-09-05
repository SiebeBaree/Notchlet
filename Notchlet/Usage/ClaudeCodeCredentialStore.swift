import CryptoKit
import Foundation

/// Claude Code's credential storage and the lock protocol Claude Code 2.1
/// runs around its own token refresh, verified from its binary: take the
/// same locks, re-read under them, adopt a token another process landed
/// first, write back with the same compare-and-swap. Keyed by config
/// directory, which is also what a second Claude Code account would be.
struct ClaudeCodeCredentialStore: Sendable {
    enum Backend: String, Sendable {
        case keychain
        case file
    }

    /// Byte for byte as stored.
    struct Stored: Sendable {
        let json: Data
        let backend: Backend
    }

    enum RefreshOutcome: Sendable {
        /// Whether this process refreshed them or another did while we
        /// waited for the lock.
        case current(ClaudeTokenRefresh.Credentials)
        case noCredentials
        /// No refresh token, or the server rejected it. Carries the
        /// rejected token so the caller can stop retrying it.
        case cannotRefresh(deadRefreshToken: String?)
        case lockBusy
        case failed
    }

    static let defaultConfigDir = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")

    let configDir: URL

    init(configDir: URL = Self.defaultConfigDir) {
        self.configDir = configDir
    }

    /// A hash of the config directory is appended when it is not the
    /// default one, as Claude Code names its item.
    var keychainService: String {
        let path = configDir.standardizedFileURL.path
        guard path != Self.defaultConfigDir.standardizedFileURL.path else {
            return "Claude Code-credentials"
        }
        let digest = SHA256.hash(data: Data(path.precomposedStringWithCanonicalMapping.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined().prefix(8)
        return "Claude Code-credentials-\(hash)"
    }

    /// Anything Claude Code would not accept falls back to its placeholder.
    static func keychainAccount(userName: String = NSUserName()) -> String {
        userName.range(of: "^[a-zA-Z0-9._-]+$", options: .regularExpression) != nil ? userName : "claude-code-user"
    }

    var fileURL: URL { configDir.appending(path: ".credentials.json") }

    var refreshLockURL: URL { configDir.appending(path: ".oauth_refresh.lock") }
    /// Claude Code takes a second, older lock beside the config directory.
    var legacyRefreshLockURL: URL { URL(filePath: configDir.resolvingSymlinksInPath().path + ".lock") }
    var storageWriteLockURL: URL { configDir.appending(path: ".storage-write.lock") }

    /// By service and account, as Claude Code does, so a read and a
    /// write-back can never land on two different items.
    func read(_ backend: Backend) async -> Stored? {
        switch backend {
        case .keychain:
            await CredentialSupport.keychainData(service: keychainService, account: Self.keychainAccount())
                .map { Stored(json: $0, backend: .keychain) }
        case .file:
            (try? Data(contentsOf: fileURL)).map { Stored(json: $0, backend: .file) }
        }
    }

    private func write(_ json: Data, to backend: Backend) async -> Bool {
        switch backend {
        case .keychain:
            return await CredentialSupport.writeKeychainItem(
                service: keychainService,
                account: Self.keychainAccount(),
                value: json
            )
        case .file:
            do {
                try json.write(to: fileURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
                return true
            } catch {
                return false
            }
        }
    }

    /// `now` is the clock for the expiry decision only; the expiry written
    /// back always comes from the system clock, so forcing a refresh with a
    /// future `now` never stores a bogus expiry.
    func refreshIfExpired(_ backend: Backend, now: Date = .now) async -> RefreshOutcome {
        // Claude Code creates the config directory before locking in it.
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        guard let lock = await DirectoryLock.acquire(refreshLockURL, stale: 60, attempts: 5, retryDelay: 1 ... 2)
        else {
            return .lockBusy
        }
        defer { lock.release() }
        guard let legacyLock = await DirectoryLock.acquire(
            legacyRefreshLockURL, stale: 60, attempts: 5, retryDelay: 1 ... 2
        ) else {
            return .lockBusy
        }
        defer { legacyLock.release() }

        // Another process may have refreshed while we waited.
        guard let stored = await read(backend),
              let credentials = ClaudeTokenRefresh.Credentials(json: stored.json)
        else {
            return .noCredentials
        }
        guard credentials.isExpired(now: now) else {
            return .current(credentials)
        }
        guard let request = ClaudeTokenRefresh.request(for: credentials) else {
            return .cannotRefresh(deadRefreshToken: nil)
        }

        let response: ClaudeTokenRefresh.Response
        do {
            let (data, urlResponse) = try await URLSession.shared.data(for: request)
            let status = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
            response = try ClaudeTokenRefresh.parse(status: status, body: data)
        } catch ClaudeTokenRefresh.Failure.invalidGrant {
            return .cannotRefresh(deadRefreshToken: credentials.refreshToken)
        } catch {
            return .failed
        }
        guard let merged = try? ClaudeTokenRefresh.merge(response, into: stored.json, now: .now),
              let refreshed = ClaudeTokenRefresh.Credentials(json: merged)
        else {
            return .failed
        }

        // Should the storage lock never free up, write anyway: a rotated
        // token that is not written back signs Claude Code out, which is
        // worse than a racing write.
        let writeLock = await DirectoryLock.acquire(storageWriteLockURL, stale: 15, attempts: 10, retryDelay: 0.1 ... 1)
        defer { writeLock?.release() }
        if let latest = await read(backend),
           ClaudeTokenRefresh.storedRefreshToken(in: latest.json) != credentials.refreshToken
        {
            // Another process won the race; its token is the live one.
            return .current(ClaudeTokenRefresh.Credentials(json: latest.json) ?? refreshed)
        }
        // Claude Code retries its own save three times too. If the store
        // still refuses, the new token is used anyway: asking the server
        // again later could only rotate a second time.
        for attempt in 1 ... 3 {
            if await write(merged, to: backend) {
                break
            }
            try? await Task.sleep(for: .milliseconds(100 * attempt))
        }
        return .current(refreshed)
    }
}
