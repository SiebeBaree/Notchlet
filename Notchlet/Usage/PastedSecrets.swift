import Foundation

/// Secrets the user pasted, in Notchlet's own keychain items. Written and
/// read through `/usr/bin/security` like every other keychain access here,
/// so no build of Notchlet, ad-hoc signed or not, ever sees a prompt for
/// them. A UserDefaults flag records that a secret exists, so the settings
/// page and the providers can tell without spawning `security`.
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

    /// Stores a trimmed secret and reports whether it was saved. Blank input
    /// is never saved.
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

    /// Removes a stored secret and reports whether it is gone. The flag is
    /// only cleared once the keychain confirms, so settings never claim a
    /// secret is removed while it is still there.
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
