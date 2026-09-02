import CryptoKit
import Foundation

/// Claude Code's credential storage as Notchlet uses it: the keychain item,
/// the credentials file it falls back to, and the lock protocol Claude Code
/// 2.1 runs around its own token refresh. Following that protocol is what
/// lets Notchlet refresh an expired token without stepping on a running
/// Claude Code: it takes the same locks, re-reads under them, adopts a
/// token another process landed first, and writes back with the same
/// compare-and-swap. Keyed by config directory, which is also what a second
/// Claude Code account would be.
struct ClaudeCodeCredentialStore: Sendable {
    enum Backend: String, Sendable {
        case keychain
        case file
    }

    /// Credentials as stored, byte for byte, and where they came from.
    struct Stored: Sendable {
        let json: Data
        let backend: Backend
    }

    enum RefreshOutcome: Sendable {
        /// Fresh credentials, whether this process refreshed them or another
        /// one did while we waited for the lock.
        case current(ClaudeTokenRefresh.Credentials)
        case noCredentials
        /// No refresh token, or the server rejected it: Claude Code has to
        /// sign in again. Carries the rejected token so the caller can stop
        /// retrying it.
        case cannotRefresh(deadRefreshToken: String?)
        /// Another process held the locks for too long; try next poll.
        case lockBusy
        /// Network or server trouble; try next poll.
        case failed
    }

    static let defaultConfigDir = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")

    let configDir: URL

    init(configDir: URL = Self.defaultConfigDir) {
        self.configDir = configDir
    }

    /// `Claude Code-credentials`, with a hash of the config directory
    /// appended when it is not the default one, exactly as Claude Code names
    /// its item.
    var keychainService: String {
        let path = configDir.standardizedFileURL.path
        guard path != Self.defaultConfigDir.standardizedFileURL.path else {
            return "Claude Code-credentials"
        }
        let digest = SHA256.hash(data: Data(path.precomposedStringWithCanonicalMapping.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined().prefix(8)
        return "Claude Code-credentials-\(hash)"
    }

    /// The login name as Claude Code stores it; anything it would not accept
    /// falls back to its placeholder.
    static func keychainAccount(userName: String = NSUserName()) -> String {
        userName.range(of: "^[a-zA-Z0-9._-]+$", options: .regularExpression) != nil ? userName : "claude-code-user"
    }

    var fileURL: URL { configDir.appending(path: ".credentials.json") }

    var refreshLockURL: URL { configDir.appending(path: ".oauth_refresh.lock") }
    /// Claude Code takes a second, older lock beside the config directory.
    var legacyRefreshLockURL: URL { URL(filePath: configDir.resolvingSymlinksInPath().path + ".lock") }
    var storageWriteLockURL: URL { configDir.appending(path: ".storage-write.lock") }

    func read(_ backend: Backend) async -> Stored? {
        switch backend {
        case .keychain:
            await CredentialSupport.keychainData(service: keychainService).map { Stored(json: $0, backend: .keychain) }
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

    /// Refreshes the stored token if it is expired, the way another Claude
    /// Code process would. Runs the whole exchange to completion: once the
    /// server has rotated the refresh token, the write-back must happen or
    /// Claude Code is left holding a dead one.
    ///
    /// `now` is the clock for the expiry decision only. The expiry written
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

        // Under the lock the store is authoritative: another process may have
        // refreshed while we waited.
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

        // Write back under Claude Code's storage lock, and only if nobody
        // rotated the refresh token in the meantime. Should the lock never
        // free up, write anyway: a rotated token that is not written back
        // signs Claude Code out, which is worse than a racing write.
        let writeLock = await DirectoryLock.acquire(storageWriteLockURL, stale: 15, attempts: 10, retryDelay: 0.1 ... 1)
        defer { writeLock?.release() }
        if let latest = await read(backend),
           ClaudeTokenRefresh.storedRefreshToken(in: latest.json) != credentials.refreshToken
        {
            // Another process won the race; its token is the live one.
            return .current(ClaudeTokenRefresh.Credentials(json: latest.json) ?? refreshed)
        }
        _ = await write(merged, to: backend)
        return .current(refreshed)
    }
}
