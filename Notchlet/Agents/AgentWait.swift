import Foundation

/// One agent session that stopped or is asking for something, and the app
/// it runs in. `host` is the bundle id of the app that launched the CLI
/// (T3 Code, Ghostty, VS Code), so bringing that app to the front can clear
/// the wait without a hover.
nonisolated struct AgentWait: Hashable, Sendable, Identifiable {
    enum Kind: String, Sendable {
        /// The turn ended and the agent is idle.
        case finished
        /// A permission prompt or a question the agent cannot pass without you.
        case needsInput
    }

    let provider: String
    let sessionID: String
    let kind: Kind
    let host: String?

    var id: String { "\(provider)/\(sessionID)" }
}
