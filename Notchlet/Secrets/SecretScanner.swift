import AppKit
import Observation

/// The scan loop and what it found, one provider at a time. New findings
/// open the notch through `alertGeneration`, once someone is at the Mac.
@Observable
final class SecretScanner {
    static let enabledDefaultsKey = "secretScanEnabled"
    static let helpURL = URL(string: "https://notchlet.com/secrets-found")!

    private let store: UsageStore
    private let stateStore: SecretStateStore
    private let defaults: UserDefaults
    private(set) var state: SecretScanState
    /// While betterleaks runs, not while the loop merely looks.
    private(set) var isScanning = false
    private(set) var failedProviderIDs: Set<String> = []
    private(set) var alertGeneration = 0
    private var loop: Task<Void, Never>?
    private var isTicking = false
    private let presence = UserPresence()

    init(store: UsageStore, stateStore: SecretStateStore = .default, defaults: UserDefaults = .standard) {
        self.store = store
        self.stateStore = stateStore
        self.defaults = defaults
        state = stateStore.load() ?? SecretScanState()
    }

    var isAvailable: Bool { Betterleaks.isAvailable }

    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledDefaultsKey)
        Analytics.capture(.settingChanged(key: "secret_scan", value: String(enabled)))
        reschedule()
    }

    /// Newest first.
    var pending: [SecretFinding] {
        state.findings.filter { $0.status == .pending }.sorted { $0.firstSeenAt > $1.firstSeenAt }
    }

    func providerName(_ id: String) -> String? {
        store.entries.first { $0.id == id }?.provider.name
    }

    enum Status: Equatable {
        case off
        case unavailable
        case waitingForIdle
        case scanning
        case failed
        case scanned(Date)
    }

    var status: Status {
        if !isAvailable {
            return .unavailable
        }
        if !isEnabled {
            return .off
        }
        if isScanning {
            return .scanning
        }
        if !failedProviderIDs.isEmpty {
            return .failed
        }
        let scans = providers.compactMap { state.lastScanAt[$0.id] }
        guard scans.count == providers.count, let latest = scans.max() else { return .waitingForIdle }
        return .scanned(latest)
    }

    private var providers: [(id: String, source: any SecretScanSource)] {
        store.entries.map(\.provider).compactMap { provider in
            guard store.isEnabled(provider.id), let source = provider.secrets else { return nil }
            return (provider.id, source)
        }
    }

    func start() {
        reschedule(after: SecretScanSchedule.launchDelay)
    }

    func reschedule(after delay: TimeInterval = 0) {
        loop?.cancel()
        loop = nil
        guard isEnabled, isAvailable else { return }
        loop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            while !Task.isCancelled {
                guard let self else { return }
                await scanDue()
                try? await Task.sleep(for: .seconds(SecretScanSchedule.tickInterval))
            }
        }
    }

    private func scanDue() async {
        guard !isTicking else { return }
        isTicking = true
        defer { isTicking = false }
        let conditions = SecretScanSchedule.Conditions(
            idleSeconds: UserPresence.idleSeconds,
            thermalState: ProcessInfo.processInfo.thermalState
        )
        var new = 0
        for provider in providers {
            let lastScanAt = state.lastScanAt[provider.id]
            let action = SecretScanSchedule.action(lastScanAt: lastScanAt, now: .now, conditions: conditions)
            guard action != .wait else { continue }
            let startedAt = Date.now
            isScanning = true
            defer { isScanning = false }
            do {
                let input = try await provider.source.input(since: lastScanAt)
                let matches = input.isEmpty ? [] : try await Betterleaks.scan(input)
                let merged = SecretFinding.merge(matches, into: state.findings, providerID: provider.id, now: startedAt)
                state.findings = merged.findings
                state.lastScanAt[provider.id] = startedAt
                try? stateStore.save(state)
                failedProviderIDs.remove(provider.id)
                new += merged.new
                Analytics.capture(.secretScanCompleted(
                    provider: provider.id,
                    kind: action == .full ? "full" : "hourly",
                    findings: matches.count,
                    new: merged.new,
                    seconds: Date.now.timeIntervalSince(startedAt)
                ))
            } catch is CancellationError {
                return
            } catch {
                failedProviderIDs.insert(provider.id)
            }
        }
        if new > 0 {
            presence.whenActive { [weak self] in
                self?.alertGeneration += 1
            }
        }
    }

    func ignore(_ id: String) {
        guard let finding = setStatus(.ignored, of: id) else { return }
        Analytics.capture(.secretIgnored(provider: finding.providerID, rule: finding.ruleID))
    }

    func ignoreAll() {
        for finding in pending {
            ignore(finding.id)
        }
    }

    /// The one place a fragment of chat content leaves the machine, on an
    /// explicit click: the preview and the rule, so noisy rules can be
    /// turned off.
    func reportFalsePositive(_ id: String) {
        guard let finding = setStatus(.falsePositive, of: id) else { return }
        Analytics.capture(.secretFalsePositive(
            provider: finding.providerID,
            rule: finding.ruleID,
            preview: finding.preview,
            length: finding.length
        ))
    }

    /// The finding stays pending until the user ignores it.
    func openHelp(_ id: String) {
        guard let finding = state.findings.first(where: { $0.id == id }) else { return }
        var components = URLComponents(url: Self.helpURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "rule", value: finding.ruleID),
            URLQueryItem(name: "provider", value: finding.providerID),
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
        Analytics.capture(.secretHelpOpened(provider: finding.providerID, rule: finding.ruleID))
    }

    @discardableResult
    private func setStatus(_ status: SecretFinding.Status, of id: String) -> SecretFinding? {
        guard let index = state.findings.firstIndex(where: { $0.id == id }) else { return nil }
        state.findings[index].status = status
        try? stateStore.save(state)
        return state.findings[index]
    }
}
