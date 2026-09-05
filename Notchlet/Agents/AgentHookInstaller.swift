import Foundation

/// Writes the hook script and puts it into each CLI's own hook config, and
/// takes exactly those entries out again. Claude Code and Codex share one
/// JSON shape (event to matcher groups to command hooks), Cursor has a flat
/// list per event, OpenCode loads a plugin file. Every other key in those
/// files is left as it was; a file that does not parse is left alone.
struct AgentHookInstaller {
    enum Target: String, CaseIterable {
        case claudeCode = "claude-code"
        case codex
        case cursor
        case opencode
    }

    /// Home for the CLI configs and the dot folder. Tests point it at a
    /// temp directory.
    var home = FileManager.default.homeDirectoryForCurrentUser

    var directory: URL { home.appending(path: ".notchlet") }
    var scriptURL: URL { directory.appending(path: "hook") }
    var socketPath: String { directory.appending(path: "hook.sock").path }

    private var script: String {
        """
        #!/bin/sh
        # Written by Notchlet. Tells the notch an agent stopped or needs you.
        # Usage: hook <provider>; the CLI's hook payload arrives on stdin.
        { printf '%s %s %s\\n' "$1" "$PPID" "${__CFBundleIdentifier:-}"; cat; } \\
          | /usr/bin/nc -U -w 2 "\(socketPath)" 2>/dev/null
        exit 0

        """
    }

    private var plugin: String {
        """
        // Written by Notchlet. Tells the notch when a session stops or asks you something.
        export const Notchlet = async ({ $ }) => ({
          event: async ({ event }) => {
            const wanted = ["session.idle", "session.status", "session.deleted", "permission.asked", "permission.replied"]
            if (!wanted.includes(event.type)) return
            await $`\(scriptURL.path) opencode < ${new Response(JSON.stringify(event))}`.quiet().nothrow()
          },
        })

        """
    }

    func install(_ targets: [Target]) {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            NSLog("Notchlet: could not write the hook script: \(error)")
            return
        }
        for target in targets {
            do {
                try apply(target, install: true)
            } catch {
                NSLog("Notchlet: could not hook into \(target.rawValue): \(error)")
            }
        }
    }

    /// Removes the hooks from every CLI that has them, whether or not it
    /// is still installed, then the script.
    func remove() {
        for target in Target.allCases {
            do {
                try apply(target, install: false)
            } catch {
                NSLog("Notchlet: could not unhook \(target.rawValue): \(error)")
            }
        }
        try? FileManager.default.removeItem(at: scriptURL)
    }

    func configURL(for target: Target) -> URL {
        switch target {
        case .claudeCode: home.appending(path: ".claude/settings.json")
        case .codex: home.appending(path: ".codex/hooks.json")
        case .cursor: home.appending(path: ".cursor/hooks.json")
        case .opencode: home.appending(path: ".config/opencode/plugins/notchlet.js")
        }
    }

    private func command(for target: Target) -> String {
        "\(scriptURL.path) \(target.rawValue)"
    }

    private func apply(_ target: Target, install: Bool) throws {
        let url = configURL(for: target)
        switch target {
        case .opencode:
            if install {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try plugin.write(to: url, atomically: true, encoding: .utf8)
            } else if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        case .claudeCode:
            try edit(url, install: install, events: ["Stop", "Notification", "UserPromptSubmit", "SessionEnd"]) {
                ["hooks": [["type": "command", "command": command(for: target), "async": true, "timeout": 5]]]
            }
        case .codex:
            try edit(
                url,
                install: install,
                events: ["Stop", "PermissionRequest", "UserPromptSubmit", "SessionEnd", "Interrupt"]
            ) {
                ["hooks": [["type": "command", "command": command(for: target), "timeout": 5]]]
            }
        case .cursor:
            try edit(url, install: install, events: ["stop", "beforeSubmitPrompt", "sessionEnd"], version: 1) {
                ["command": command(for: target)]
            }
        }
    }

    /// Rewrites the `hooks` object of a JSON file: for each event, drops the
    /// entries that are Notchlet's and appends a fresh one when installing.
    /// Removing from a file that does not exist is a no-op; installing
    /// creates it.
    private func edit(
        _ url: URL, install: Bool, events: [String], version: Int? = nil, entry: () -> [String: Any]
    ) throws {
        var root: [String: Any]
        if let data = try? Data(contentsOf: url) {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            root = parsed
        } else if install {
            root = [:]
        } else {
            return
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var entries = (hooks[event] as? [[String: Any]] ?? [])
                .filter { !Self.isNotchlet($0, script: scriptURL.path) }
            if install {
                entries.append(entry())
            }
            hooks[event] = entries.isEmpty ? nil : entries
        }
        if hooks.isEmpty, root["hooks"] == nil {
            // Never existed and nothing to add: leave the file alone.
        } else {
            root["hooks"] = hooks
        }
        if let version, root["version"] == nil {
            root["version"] = version
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url, options: .atomic)
    }

    /// An entry is Notchlet's when its command, or every command in its
    /// group, is exactly the hook script with one of the provider tags.
    static func isNotchlet(_ entry: [String: Any], script: String) -> Bool {
        let commands = Set(Target.allCases.map { "\(script) \($0.rawValue)" })
        if let command = entry["command"] as? String {
            return commands.contains(command)
        }
        if let group = entry["hooks"] as? [[String: Any]], !group.isEmpty {
            return group.allSatisfy { commands.contains($0["command"] as? String ?? "") }
        }
        return false
    }
}
