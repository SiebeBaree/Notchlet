import AppKit
import Observation

/// Agents that stopped or need an answer, fed by the CLIs' own hooks over
/// `HookSocket`. The notch draws an outline while this is non-empty, amber
/// when any of them needs input. Nothing here persists: after a relaunch
/// the agents that were waiting fire again on their next turn, and a stale
/// outline after a crash would be worse than a missed one.
///
/// A wait clears when the notch opens, when the app hosting the CLI comes
/// to the front, when the session gets its next prompt, or when it ends.
/// A hook from an app that is already frontmost never shows: the person
/// is looking at it.
@Observable
final class AgentWaits {
    static let enabledDefaultsKey = "agentWaitEnabled"

    private let defaults: UserDefaults
    private let installedProviderIDs: () -> [String]
    private let socket = HookSocket()
    private let installer = AgentHookInstaller()
    private(set) var waits: [AgentWait] = []

    init(defaults: UserDefaults = .standard, installedProviderIDs: @escaping () -> [String]) {
        self.defaults = defaults
        self.installedProviderIDs = installedProviderIDs
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.enabledDefaultsKey) }
    var isWaiting: Bool { !waits.isEmpty }
    var needsInput: Bool { waits.contains { $0.kind == .needsInput } }

    /// Puts the hooks back into every installed CLI (a CLI installed since
    /// last launch, or one whose update dropped them) and starts listening.
    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        guard isEnabled else { return }
        installer.install(targets)
        listen()
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledDefaultsKey)
        if enabled {
            installer.install(targets)
            listen()
        } else {
            installer.remove()
            socket.stop()
            waits = []
        }
        Analytics.capture(.settingChanged(key: "agent_wait", value: String(enabled)))
    }

    /// The notch opened; whatever was waiting has been seen.
    func clearAll(by reason: String) {
        guard !waits.isEmpty else { return }
        waits = []
        Analytics.capture(.agentWaitCleared(by: reason))
    }

    /// One message from the hook script.
    func receive(_ data: Data) {
        guard let message = AgentWaitRules.parse(data) else { return }
        let id = message.waitID
        switch message.effect {
        case .ignore:
            return
        case .clear:
            if waits.contains(where: { $0.id == id }) {
                waits.removeAll { $0.id == id }
                Analytics.capture(.agentWaitCleared(by: "prompt"))
            }
        case let .wait(kind):
            let host = HostApp.resolve(bundleID: message.bundleID, pid: message.pid)
            waits.removeAll { $0.id == id }
            // Watching the agent work is not waiting for it.
            if let host, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == host {
                return
            }
            waits.insert(
                AgentWait(provider: message.provider, sessionID: message.sessionID, kind: kind, host: host),
                at: 0
            )
            Analytics.capture(.agentWaitShown(provider: message.provider.rawValue, kind: kind.rawValue))
        }
    }

    private var targets: [AgentCLI] {
        installedProviderIDs().compactMap(AgentCLI.init(rawValue:))
    }

    private func listen() {
        do {
            try socket.start { [weak self] data in
                self?.receive(data)
            }
        } catch {
            NSLog("Notchlet: hook socket failed: \(error)")
        }
    }

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier
        else { return }
        let remaining = waits.filter { !AgentWaitRules.clears($0, activated: bundleID) }
        if remaining.count != waits.count {
            waits = remaining
            Analytics.capture(.agentWaitCleared(by: "focus"))
        }
    }
}
