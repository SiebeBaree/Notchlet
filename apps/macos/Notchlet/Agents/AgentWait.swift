import Foundation

/// The raw value is the provider id and the tag the hook script sends.
nonisolated enum AgentCLI: String, CaseIterable, Sendable {
    case claudeCode = "claude-code"
    case codex
    case cursor
    case opencode
}

/// One agent session that stopped or is asking for something. `host` is
/// the bundle id of the app that launched the CLI, so bringing it to the
/// front clears the wait without a hover.
nonisolated struct AgentWait: Hashable, Sendable, Identifiable {
    enum Kind: String, Sendable {
        case finished
        /// A permission prompt or a question.
        case needsInput
    }

    let provider: AgentCLI
    let sessionID: String
    let kind: Kind
    let host: String?

    var id: String { "\(provider.rawValue)/\(sessionID)" }
}
