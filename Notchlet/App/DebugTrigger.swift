#if DEBUG
    import Foundation
    import notify

    /// Fires a feature by hand while running from Xcode: the Fire row in
    /// settings, or `notifyutil -p com.notchlet.debug.<name>` from a shell.
    /// Nothing fired here is saved, so the next launch starts clean.
    enum DebugTrigger: String, CaseIterable {
        case usageAlert = "alert"
        case leakedSecret = "secret"
        case agentFinished = "finished"
        case agentNeedsInput = "input"

        struct Targets {
            let store: UsageStore
            let scanner: SecretScanner
            let alerts: UsageAlerts
            let waits: AgentWaits
        }

        var title: String {
            switch self {
            case .usageAlert: "Usage alert"
            case .leakedSecret: "Leaked secret"
            case .agentFinished: "Agent finished"
            case .agentNeedsInput: "Agent asks"
            }
        }

        var notifyName: String { "com.notchlet.debug.\(rawValue)" }

        func fire(_ targets: Targets) {
            switch self {
            case .usageAlert:
                // The first provider with data, else the first one on with a
                // made-up window, so the card renders without a real fetch.
                let store = targets.store
                let entry = store.entries.first { store.isEnabled($0.id) && $0.snapshot?.primaryWindow != nil }
                    ?? store.entries.first { store.isEnabled($0.id) }
                    ?? store.entries.first
                guard let entry else { return }
                let window = entry.snapshot?.primaryWindow ?? UsageWindow(
                    id: "session", label: "5h", duration: 5 * 3600, usedFraction: 0.83,
                    resetsAt: .now.addingTimeInterval(3600)
                )
                targets.alerts.showTestNotice(providerID: entry.id, window: window)
            case .leakedSecret:
                let providerID = targets.store.entries.first { $0.provider.secrets != nil }?.id ?? AgentCLI.claudeCode
                    .rawValue
                targets.scanner.showTestFinding(providerID: providerID)
            case .agentFinished:
                targets.waits.showTestWait(kind: .finished)
            case .agentNeedsInput:
                targets.waits.showTestWait(kind: .needsInput)
            }
        }

        static func listen(_ targets: Targets) {
            for trigger in allCases {
                var token: Int32 = 0
                notify_register_dispatch(trigger.notifyName, &token, .main) { _ in
                    MainActor.assumeIsolated {
                        trigger.fire(targets)
                    }
                }
            }
        }
    }
#endif
