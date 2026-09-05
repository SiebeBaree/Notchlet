import Foundation
@testable import Notchlet
import Testing

struct AgentHookInstallerTests {
    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "notchlet-hooks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func json(at url: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    @Test func installKeepsOtherKeysAndHooksAndRemoveTakesOnlyOurs() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = AgentHookInstaller(home: home)
        let settings = installer.configURL(for: .claudeCode)
        try FileManager.default.createDirectory(
            at: settings.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("""
        {"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]},"tui":"fullscreen"}
        """.utf8).write(to: settings)

        installer.install([.claudeCode])
        var root = try json(at: settings)
        #expect(root["model"] as? String == "opus")
        #expect(root["tui"] as? String == "fullscreen")
        var hooks = try #require(root["hooks"] as? [String: Any])
        let stop = try #require(hooks["Stop"] as? [[String: Any]])
        #expect(stop.count == 2)
        #expect((stop[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String == "say done")
        let ours = try #require((stop[1]["hooks"] as? [[String: Any]])?.first)
        #expect(ours["command"] as? String == "\(installer.scriptURL.path) claude-code")
        #expect(ours["async"] as? Bool == true)
        #expect(hooks["Notification"] != nil)
        #expect(hooks["UserPromptSubmit"] != nil)
        #expect(hooks["SessionEnd"] != nil)
        let script = try String(contentsOf: installer.scriptURL, encoding: .utf8)
        #expect(script.hasPrefix("#!/bin/sh"))
        #expect(script.contains(installer.socketPath))

        // Installing twice does not stack entries.
        installer.install([.claudeCode])
        root = try json(at: settings)
        #expect(((root["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.count == 2)

        installer.remove()
        root = try json(at: settings)
        hooks = try #require(root["hooks"] as? [String: Any])
        #expect((hooks["Stop"] as? [[String: Any]])?.count == 1)
        #expect(hooks["Notification"] == nil)
        #expect(hooks["SessionEnd"] == nil)
        #expect(root["model"] as? String == "opus")
        #expect(!FileManager.default.fileExists(atPath: installer.scriptURL.path))
    }

    @Test func codexCursorAndOpenCodeFiles() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = AgentHookInstaller(home: home)

        installer.install([.codex, .cursor, .opencode])

        let codex = try json(at: installer.configURL(for: .codex))
        let codexHooks = try #require(codex["hooks"] as? [String: Any])
        #expect(Set(codexHooks.keys) == ["Stop", "PermissionRequest", "UserPromptSubmit", "SessionEnd", "Interrupt"])
        let codexEntry = try #require(((codexHooks["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?
            .first)
        #expect(codexEntry["async"] == nil)

        let cursor = try json(at: installer.configURL(for: .cursor))
        #expect(cursor["version"] as? Int == 1)
        let cursorStop = try #require((cursor["hooks"] as? [String: Any])?["stop"] as? [[String: Any]])
        #expect(cursorStop.first?["command"] as? String == "\(installer.scriptURL.path) cursor")

        let plugin = try String(contentsOf: installer.configURL(for: .opencode), encoding: .utf8)
        #expect(plugin.contains("session.idle"))
        #expect(plugin.contains("\(installer.scriptURL.path) opencode"))

        installer.remove()
        #expect(!FileManager.default.fileExists(atPath: installer.configURL(for: .opencode).path))
        #expect(try (json(at: installer.configURL(for: .codex))["hooks"] as? [String: Any])?.isEmpty == true)
    }

    @Test func aFileThatDoesNotParseIsLeftAlone() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = AgentHookInstaller(home: home)
        let settings = installer.configURL(for: .claudeCode)
        try FileManager.default.createDirectory(
            at: settings.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{ not json".utf8).write(to: settings)

        installer.install([.claudeCode])

        #expect(try String(contentsOf: settings, encoding: .utf8) == "{ not json")
    }

    @Test func removingFromAMissingFileCreatesNothing() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = AgentHookInstaller(home: home)

        installer.remove()

        #expect(!FileManager.default.fileExists(atPath: installer.configURL(for: .codex).path))
        #expect(!FileManager.default.fileExists(atPath: installer.configURL(for: .cursor).path))
    }
}
