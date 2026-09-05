import AppKit
import Observation

/// Scans the enabled providers' chats for leaked keys and keeps what it
/// found: a first full pass when the Mac is idle, then hourly over what
/// changed, one provider at a time. New findings open the notch through
/// `alertGeneration`, once someone is at the Mac to see it.
@Observable
final class SecretScanner {
    static let enabledDefaultsKey = "secretScanEnabled"
    static let helpURL = URL(string: "https://notchlet.com/secrets-found")!

    private let store: UsageStore
    private let stateStore: SecretStateStore
    private(set) var state: SecretScanState
    /// True while betterleaks is running, not while the loop merely looks.
    private(set) var isScanning = false
    /// Providers whose last scan threw; the next tick tries again.
    private(set) var failedProviderIDs: Set<String> = []
    /// Bumped when new findings should open the notch.
    private(set) var alertGeneration = 0
    private var loop: Task<Void, Never>?
    private var isTicking = false
    /// Holds an alert from a scan that finished while the user was away
    /// until they are back.
    private let presence = UserPresence()

    init(store: UsageStore, stateStore: SecretStateStore = .default) {
        self.store = store
        self.stateStore = stateStore
        state = stateStore.load() ?? SecretScanState()
    }

    /// False on Intel and in a build without the helper.
    var isAvailable: Bool { Betterleaks.isAvailable }

    /// On by default; the settings toggle flips it.
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledDefaultsKey)
        Analytics.capture(.settingChanged(key: "secret_scan", value: String(enabled)))
        reschedule()
    }

    /// Findings waiting for the user, newest first.
    var pending: [SecretFinding] {
        state.findings.filter { $0.status == .pending }.sorted { $0.firstSeenAt > $1.firstSeenAt }
    }

    func providerName(_ id: String) -> String? {
        store.entries.first { $0.id == id }?.provider.name
    }

    /// What the scanner is up to, for the pane and the settings line.
    enum Status: Equatable {
        case off
        case unavailable
        /// Some provider has never been scanned; the first pass waits for
        /// an idle moment.
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

    /// Providers that are on and have chats on disk to read.
    private var providers: [(id: String, source: any SecretScanSource)] {
        store.entries.map(\.provider).compactMap { provider in
            guard store.isEnabled(provider.id), let source = provider.secrets else { return nil }
            return (provider.id, source)
        }
    }

    func start() {
        reschedule(after: SecretScanSchedule.launchDelay)
    }

    /// Restarts the loop: what a wake from sleep or the toggle calls.
    func reschedule() {
        reschedule(after: 0)
    }

    private func reschedule(after delay: TimeInterval) {
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
                // Left undated, so the next tick tries again.
                failedProviderIDs.insert(provider.id)
            }
        }
        if new > 0 {
            presence.whenActive { [weak self] in
                self?.alertGeneration += 1
            }
        }
    }

    // MARK: Actions

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
    /// turned off in a later release.
    func reportFalsePositive(_ id: String) {
        guard let finding = setStatus(.falsePositive, of: id) else { return }
        Analytics.capture(.secretFalsePositive(
            provider: finding.providerID,
            rule: finding.ruleID,
            preview: finding.preview,
            length: finding.length
        ))
    }

    /// Opens the website's page for this kind of key. The finding stays
    /// pending until the user ignores it.
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
