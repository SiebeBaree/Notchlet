import Foundation

/// One way a provider can obtain credentials: the CLI's own login, a file,
/// or a secret the user pasted into settings. Providers list their options
/// in order of preference; `AuthSelection.auto` walks that list and the
/// first option with a usable credential wins.
struct AuthOption: Identifiable, Hashable, Sendable {
    let id: String
    /// Short label for the settings picker, e.g. "Claude Code".
    let label: String
    /// For options where the user supplies the secret, what to call it in
    /// the UI ("session token", "API key"). Nil for options that read the
    /// CLI's own state.
    var secretName: String?
}

/// The user's choice for one provider: let Notchlet pick, or use one option
/// only. Keyed by provider id in UserDefaults, so a second account of the
/// same provider later is just another id.
enum AuthSelection: Hashable, Sendable {
    case auto
    case option(String)

    /// The options to try, in order. Auto tries all of them.
    func resolve(_ options: [AuthOption]) -> [AuthOption] {
        switch self {
        case .auto: options
        case let .option(id): options.filter { $0.id == id }
        }
    }

    var storedValue: String {
        switch self {
        case .auto: "auto"
        case let .option(id): id
        }
    }

    /// A stored value naming an option the provider no longer has reads as
    /// auto, so a renamed option never strands anyone on nothing.
    init(storedValue: String?, options: [AuthOption]) {
        if let storedValue, options.contains(where: { $0.id == storedValue }) {
            self = .option(storedValue)
        } else {
            self = .auto
        }
    }
}

enum ProviderAuthSettings {
    static func selectionDefaultsKey(_ providerID: String) -> String {
        "providerAuth.\(providerID)"
    }

    static func selection(for providerID: String, options: [AuthOption]) -> AuthSelection {
        AuthSelection(
            storedValue: UserDefaults.standard.string(forKey: selectionDefaultsKey(providerID)),
            options: options
        )
    }

    static func setSelection(_ selection: AuthSelection, for providerID: String) {
        UserDefaults.standard.set(selection.storedValue, forKey: selectionDefaultsKey(providerID))
    }
}

/// Why a provider had no usable credential, from least to most specific.
/// When auto tries several options the most specific problem is the one
/// reported, so an expired login is never masked by an empty fallback.
enum AuthProblem: Int, Comparable, Sendable {
    /// Nothing to read: the CLI is not signed in, or no secret was pasted.
    case signedOut
    /// A credential exists but is past its expiry and could not be renewed.
    case expired
    /// The usage endpoint rejected the credential.
    case rejected

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Secrets the user pasted, in Notchlet's own keychain items. Written and
/// read through `/usr/bin/security` like every other keychain access here,
/// so no build of Notchlet, ad-hoc signed or not, ever sees a prompt for
/// them. A UserDefaults flag records that a secret exists, so the settings
/// page and the providers can tell without spawning `security`.
enum SecretStore {
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

    static func remove(providerID: String, optionID: String) async {
        await CredentialSupport.deleteKeychainItem(
            service: service,
            account: account(providerID: providerID, optionID: optionID)
        )
        UserDefaults.standard.removeObject(forKey: flagDefaultsKey(providerID: providerID, optionID: optionID))
    }
}
