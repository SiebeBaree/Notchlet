import Foundation

/// What one hook message does to the wait list.
nonisolated enum AgentHookEffect: Equatable, Sendable {
    case wait(AgentWait.Kind)
    case clear
    case ignore
}

/// A hook message after parsing: the script's header line resolved against
/// the CLI's own payload.
nonisolated struct AgentHookMessage: Equatable, Sendable {
    let provider: AgentCLI
    let sessionID: String
    /// The CLI's pid as the script saw it, the start of the parent walk.
    let pid: pid_t
    /// `__CFBundleIdentifier` of the process, set by LaunchServices for
    /// everything a GUI app starts. Empty when the CLI came from ssh or a
    /// launchd job.
    let bundleID: String?
    let effect: AgentHookEffect

    /// The `AgentWait.id` this message is about.
    var waitID: String { "\(provider.rawValue)/\(sessionID)" }
}

/// The pure side of agent waits: turning the bytes the hook script sends
/// into a message, and deciding what each CLI's event means. Nothing here
/// touches AppKit or the file system, so every branch has a test.
nonisolated enum AgentWaitRules {
    /// Claude Code notification types that mean a person has to answer.
    static let claudeNeedsInputTypes: Set<String> = [
        "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input",
    ]

    /// Apps that host a CLI. The fallback for a wait with no host: when any
    /// of these comes to the front, the person went to look at a terminal.
    static let terminalHosts: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm", "co.zeit.hyper", "org.tabby",
        "com.raphaelamorim.rio", "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "dev.zed.Zed", "com.t3tools.t3code",
        "com.anthropic.claudefordesktop", "com.openai.codex", "com.conductor.app",
    ]

    /// Whether an app coming to the front should clear a wait.
    static func clears(_ wait: AgentWait, activated bundleID: String) -> Bool {
        if let host = wait.host {
            return host == bundleID
        }
        return terminalHosts.contains(bundleID) || bundleID.hasPrefix("com.jetbrains.")
    }

    /// Parses `provider pid bundleid\n{json}`. The provider tag is the
    /// script's argument; Cursor also runs hooks it finds in Claude Code's
    /// settings, so the payload has the final say.
    static func parse(_ data: Data) -> AgentHookMessage? {
        guard let newline = data.firstIndex(of: UInt8(ascii: "\n")),
              let header = String(data: data[data.startIndex ..< newline], encoding: .utf8)
        else { return nil }
        let fields = header.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard fields.count >= 2, let pid = pid_t(fields[1]) else { return nil }
        let body = data[data.index(after: newline)...]
        guard let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        let bundleID = fields.count > 2 ? String(fields[2]).trimmingCharacters(in: .whitespaces) : ""
        guard let provider = resolveProvider(tag: String(fields[0]), payload: payload),
              let sessionID = sessionID(provider: provider, payload: payload)
        else { return nil }
        return AgentHookMessage(
            provider: provider,
            sessionID: sessionID,
            pid: pid,
            bundleID: bundleID.isEmpty ? nil : bundleID,
            effect: effect(provider: provider, payload: payload)
        )
    }

    static func resolveProvider(tag: String, payload: [String: Any]) -> AgentCLI? {
        payload["cursor_version"] != nil ? .cursor : AgentCLI(rawValue: tag)
    }

    static func sessionID(provider: AgentCLI, payload: [String: Any]) -> String? {
        switch provider {
        case .cursor:
            payload["conversation_id"] as? String
        case .opencode:
            (payload["properties"] as? [String: Any])?["sessionID"] as? String
        case .claudeCode, .codex:
            payload["session_id"] as? String
        }
    }

    static func effect(provider: AgentCLI, payload: [String: Any]) -> AgentHookEffect {
        let event = payload["hook_event_name"] as? String
        switch provider {
        case .claudeCode:
            switch event {
            case "Stop": return .wait(.finished)
            case "Notification":
                let type = payload["notification_type"] as? String ?? ""
                return claudeNeedsInputTypes.contains(type) ? .wait(.needsInput) : .ignore
            case "UserPromptSubmit", "SessionEnd": return .clear
            default: return .ignore
            }
        case .codex:
            switch event {
            case "Stop": return .wait(.finished)
            case "PermissionRequest": return .wait(.needsInput)
            case "UserPromptSubmit", "SessionEnd", "Interrupt": return .clear
            default: return .ignore
            }
        case .cursor:
            switch event {
            case "stop": return payload["status"] as? String == "completed" ? .wait(.finished) : .clear
            case "beforeSubmitPrompt", "sessionEnd": return .clear
            default: return .ignore
            }
        case .opencode:
            let properties = payload["properties"] as? [String: Any]
            switch payload["type"] as? String {
            case "session.idle": return .wait(.finished)
            case "permission.asked": return .wait(.needsInput)
            case "session.status":
                switch (properties?["status"] as? [String: Any])?["type"] as? String {
                case "busy": return .clear
                case "idle": return .wait(.finished)
                default: return .ignore
                }
            case "session.deleted", "permission.replied": return .clear
            default: return .ignore
            }
        }
    }
}
