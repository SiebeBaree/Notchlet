import Foundation
@testable import Notchlet
import Testing

struct AgentWaitRulesTests {
    private func message(_ tag: String, _ pid: String = "4242", _ bundle: String = "",
                         json: String) -> AgentHookMessage?
    {
        AgentWaitRules.parse(Data("\(tag) \(pid) \(bundle)\n\(json)".utf8))
    }

    @Test func claudeStopIsFinishedAndPromptClears() {
        let stop = message("claude-code", "4242", "com.t3tools.t3code", json: """
        {"session_id":"abc","cwd":"/tmp","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"Done"}
        """)
        #expect(stop == AgentHookMessage(
            provider: .claudeCode, sessionID: "abc", pid: 4242, bundleID: "com.t3tools.t3code",
            effect: .wait(.finished)
        ))
        let prompt = message(
            "claude-code",
            json: #"{"session_id":"abc","hook_event_name":"UserPromptSubmit","prompt":"go"}"#
        )
        #expect(prompt?.effect == .clear)
        let end = message(
            "claude-code",
            json: #"{"session_id":"abc","hook_event_name":"SessionEnd","session_end_reason":"other"}"#
        )
        #expect(end?.effect == .clear)
    }

    @Test func claudeNotificationsOnlyCountWhenSomeoneHasToAnswer() {
        func effect(_ type: String) -> AgentHookEffect? {
            message("claude-code", json: """
            {"session_id":"abc","hook_event_name":"Notification","notification_type":"\(type)","message":"m"}
            """)?.effect
        }
        #expect(effect("permission_prompt") == .wait(.needsInput))
        #expect(effect("elicitation_dialog") == .wait(.needsInput))
        #expect(effect("agent_needs_input") == .wait(.needsInput))
        #expect(effect("auth_success") == .ignore)
        #expect(effect("idle_prompt") == .ignore)
    }

    @Test func codexEvents() {
        func effect(_ event: String) -> AgentHookEffect? {
            message("codex", json: #"{"session_id":"t1","cwd":"/tmp","hook_event_name":"\#(event)","turn_id":"u"}"#)?
                .effect
        }
        #expect(effect("Stop") == .wait(.finished))
        #expect(effect("PermissionRequest") == .wait(.needsInput))
        #expect(effect("UserPromptSubmit") == .clear)
        #expect(effect("Interrupt") == .clear)
        #expect(effect("PreToolUse") == .ignore)
    }

    @Test func cursorStopOnlyWhenCompleted() {
        let done = message("cursor", json: """
        {"conversation_id":"c1","hook_event_name":"stop","status":"completed","loop_count":0,"cursor_version":"1.9"}
        """)
        #expect(done?.sessionID == "c1")
        #expect(done?.effect == .wait(.finished))
        let aborted = message("cursor", json: #"{"conversation_id":"c1","hook_event_name":"stop","status":"aborted"}"#)
        #expect(aborted?.effect == .clear)
        let prompt = message("cursor", json: #"{"conversation_id":"c1","hook_event_name":"beforeSubmitPrompt"}"#)
        #expect(prompt?.effect == .clear)
    }

    @Test func cursorRunningClaudeHooksIsStillCursor() {
        // Cursor reads Claude Code's settings.json hooks and fires them
        // with its own payload, so the script's tag would say claude-code.
        let parsed = message("claude-code", json: """
        {"conversation_id":"c9","hook_event_name":"stop","status":"completed","cursor_version":"1.9"}
        """)
        #expect(parsed?.provider == .cursor)
        #expect(parsed?.sessionID == "c9")
    }

    @Test func opencodeEvents() {
        func effect(_ json: String) -> AgentHookEffect? {
            message("opencode", json: json)?.effect
        }
        #expect(effect(#"{"type":"session.idle","properties":{"sessionID":"s1"}}"#) == .wait(.finished))
        #expect(effect(#"{"type":"permission.asked","properties":{"id":"p","sessionID":"s1","permission":"bash"}}"#)
            == .wait(.needsInput))
        #expect(effect(#"{"type":"session.status","properties":{"sessionID":"s1","status":{"type":"busy"}}}"#) ==
            .clear)
        #expect(effect(#"{"type":"session.status","properties":{"sessionID":"s1","status":{"type":"idle"}}}"#)
            == .wait(.finished))
        #expect(effect(#"{"type":"session.deleted","properties":{"sessionID":"s1"}}"#) == .clear)
        #expect(effect(#"{"type":"message.updated","properties":{"sessionID":"s1"}}"#) == .ignore)
    }

    @Test func malformedMessagesAreDropped() {
        #expect(AgentWaitRules.parse(Data("claude-code 12\n".utf8)) == nil)
        #expect(AgentWaitRules.parse(Data("claude-code\n{}".utf8)) == nil)
        #expect(message("claude-code", json: #"{"hook_event_name":"Stop"}"#) == nil)
        #expect(message("claude-code", "notapid", json: #"{"session_id":"a","hook_event_name":"Stop"}"#) == nil)
    }

    @Test func emptyBundleIsNoHost() {
        let parsed = message("codex", "77", "", json: #"{"session_id":"a","hook_event_name":"Stop"}"#)
        #expect(parsed?.bundleID == nil)
        #expect(parsed?.pid == 77)
    }

    @Test func focusClearsTheHostOrAnyTerminalWhenUnknown() {
        let hosted = AgentWait(
            provider: .codex,
            sessionID: "a",
            kind: .finished,
            host: "com.t3tools.t3code"
        )
        #expect(AgentWaitRules.clears(hosted, activated: "com.t3tools.t3code"))
        #expect(!AgentWaitRules.clears(hosted, activated: "com.mitchellh.ghostty"))
        let orphan = AgentWait(provider: .codex, sessionID: "b", kind: .finished, host: nil)
        #expect(AgentWaitRules.clears(orphan, activated: "com.mitchellh.ghostty"))
        #expect(AgentWaitRules.clears(orphan, activated: "com.jetbrains.WebStorm"))
        #expect(!AgentWaitRules.clears(orphan, activated: "com.apple.Safari"))
    }
}
