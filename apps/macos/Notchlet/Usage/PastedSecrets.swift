import Foundation

/// Secrets the user pasted, in Notchlet's own keychain items, through
/// `/usr/bin/security` like every other keychain access here so no build
/// ever sees a prompt for them. A UserDefaults flag records that a secret
/// exists, so callers can tell without spawning `security`.
enum PastedSecrets {
    static let service = "Notchlet"

    static func account(providerID: String, optionID: String) -> String {
        "\(providerID).\(optionID)"
    }

    static func flagDefaultsKey(providerID: String, optionID: String) -> String {
        "providerSecret.\(providerID).\(optionID)"
    }

    static func hasSecret(providerID: String, optionID: String) -> Bool {
        UserDefaults.standard.bool(forKey: flagDefaultsKey(providerID: providerID, optionID: optionID))
    }

    static func read(providerID: String, optionID: String) async -> String? {
        guard hasSecret(providerID: providerID, optionID: optionID) else { return nil }
        return await CredentialSupport.keychainString(
            service: service,
            account: account(providerID: providerID, optionID: optionID)
        )
    }

    /// Blank input is never saved.
    @discardableResult
    static func save(_ secret: String, providerID: String, optionID: String) async -> Bool {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let saved = await CredentialSupport.writeKeychainItem(
            service: service,
            account: account(providerID: providerID, optionID: optionID),
            value: Data(trimmed.utf8)
        )
        if saved {
            UserDefaults.standard.set(true, forKey: flagDefaultsKey(providerID: providerID, optionID: optionID))
        }
        return saved
    }

    /// The flag clears only once the keychain confirms, so settings never
    /// claim a secret is gone while it is still there.
    @discardableResult
    static func remove(providerID: String, optionID: String) async -> Bool {
        let removed = await CredentialSupport.deleteKeychainItem(
            service: service,
            account: account(providerID: providerID, optionID: optionID)
        )
        if removed {
            UserDefaults.standard.removeObject(forKey: flagDefaultsKey(providerID: providerID, optionID: optionID))
        }
        return removed
    }
}
