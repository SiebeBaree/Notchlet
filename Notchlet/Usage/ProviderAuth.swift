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
/// only. The raw value ("auto" or the option id) is what UserDefaults keeps.
nonisolated enum AuthSelection: Hashable, Sendable, RawRepresentable {
    case auto
    case option(String)

    init(rawValue: String) {
        self = rawValue == "auto" ? .auto : .option(rawValue)
    }

    var rawValue: String {
        switch self {
        case .auto: "auto"
        case let .option(id): id
        }
    }

    /// The options to try, in order. Auto tries all of them.
    func resolve(_ options: [AuthOption]) -> [AuthOption] {
        switch self {
        case .auto: options
        case let .option(id): options.filter { $0.id == id }
        }
    }

    /// A choice naming an option the provider no longer has reads as auto,
    /// so a renamed option never strands anyone on nothing.
    func validated(against options: [AuthOption]) -> AuthSelection {
        if case let .option(id) = self, !options.contains(where: { $0.id == id }) {
            return .auto
        }
        return self
    }

    /// Tries the options this choice allows, in order, and answers from the
    /// first one with a usable credential. The most specific problem is
    /// reported when none works, so an expired login is never reported as
    /// merely signed out because an empty fallback came last. Anything
    /// else, a rate limit or a network failure, stops the walk.
    func firstUsable<T>(
        _ options: [AuthOption],
        _ body: (AuthOption) async throws -> T
    ) async throws -> T {
        var problem = AuthProblem.signedOut
        for option in resolve(options) {
            do {
                return try await body(option)
            } catch let ProviderError.notAvailable(found) {
                problem = max(problem, found)
            }
        }
        throw ProviderError.notAvailable(problem)
    }
}

/// The per-provider `AuthSelection` in UserDefaults, keyed by provider id
/// so a second account of one provider later is just another id.
enum ProviderAuthSettings {
    static func selectionDefaultsKey(_ providerID: String) -> String {
        "providerAuth.\(providerID)"
    }

    static func selection(for providerID: String, options: [AuthOption]) -> AuthSelection {
        let stored = UserDefaults.standard.string(forKey: selectionDefaultsKey(providerID)) ?? "auto"
        return AuthSelection(rawValue: stored).validated(against: options)
    }

    static func setSelection(_ selection: AuthSelection, for providerID: String) {
        UserDefaults.standard.set(selection.rawValue, forKey: selectionDefaultsKey(providerID))
    }
}

/// Why a provider had no usable credential, from least to most specific.
/// When auto tries several options the most specific problem is the one
/// reported, so an expired login is never masked by an empty fallback.
nonisolated enum AuthProblem: Int, Comparable, Sendable {
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
