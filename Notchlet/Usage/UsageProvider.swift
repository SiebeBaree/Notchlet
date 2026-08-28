import Foundation

/// A source of usage data for one agent CLI.
///
/// Implementations read the CLI's local state (credentials, session logs) or
/// call the same usage endpoint the CLI itself calls. They should never
/// consume usage: fetching a snapshot must not count against any limit.
protocol UsageProvider {
    /// Stable identifier, used as a dictionary key and for settings.
    var id: String { get }
    /// Display name shown in the UI.
    var name: String { get }

    func fetchUsage() async throws -> UsageSnapshot
}

enum UsageProviderError: Error {
    /// The provider is scaffolded but not implemented yet.
    case notImplemented
    /// The CLI is not installed or has never been logged in.
    case notAvailable
}
