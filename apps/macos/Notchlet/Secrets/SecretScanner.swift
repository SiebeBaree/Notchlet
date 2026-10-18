import AppKit
import Observation

/// The scan loop and what it found, one provider at a time. The notch
/// stays open on `pending` until every finding is dealt with.
@Observable
final class SecretScanner {
    static let enabledDefaultsKey = "secretScanEnabled"
    static let helpURL = URL(string: "https://notchlet.com/secrets-found")!

    private let store: UsageStore
    private let stateStore: SecretStateStore
    private let defaults: UserDefaults
    private let available: Bool
    private let scan: @Sendable (SecretScanInput) async throws -> [SecretMatch]
    private let readConditions: () -> SecretScanSchedule.Conditions
    private(set) var state: SecretScanState
    /// While betterleaks runs, not while the loop merely looks.
    private(set) var isScanning = false
    private(set) var failedProviderIDs: Set<String> = []
    /// `DebugTrigger`'s made-up finding, kept out of the saved state; empty
    /// in release builds.
    private var testFindings: [SecretFinding] = []
    private(set) var nextScanAt = Date.now.addingTimeInterval(SecretScanSchedule.launchDelay)
    private var retries: [String: (failures: Int, at: Date)] = [:]
    private var generation = 0
    @ObservationIgnored private var activeScan: Task<[SecretMatch], any Error>?
    private var isTicking = false

    init(store: UsageStore, stateStore: SecretStateStore = .default, defaults: UserDefaults = .standard,
         available: Bool = Betterleaks.isAvailable,
         scan: @escaping @Sendable (SecretScanInput) async throws -> [SecretMatch] = { try await Betterleaks.scan($0) },
         conditions: @escaping () -> SecretScanSchedule.Conditions = {
             .init(idleSeconds: UserPresence.idleSeconds, thermalState: ProcessInfo.processInfo.thermalState,
                   isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
         })
    {
        self.store = store
        self.stateStore = stateStore
        self.defaults = defaults
        self.available = available
        self.scan = scan
        readConditions = conditions
        state = stateStore.load() ?? SecretScanState()
        state.useRules(Betterleaks.rulesVersion)
    }

    var isAvailable: Bool { available }

    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledDefaultsKey) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledDefaultsKey)
        Analytics.capture(.settingChanged(key: "secret_scan", value: String(enabled)))
        generation += 1
        if !enabled {
            activeScan?.cancel()
        }
        nextScanAt = .now
        store.reschedule()
    }

    /// Newest first.
    var pending: [SecretFinding] {
        (state.findings + testFindings).filter { $0.status == .pending }.sorted { $0.firstSeenAt > $1.firstSeenAt }
    }

    #if DEBUG
        func showTestFinding(providerID: String) {
            testFindings = [SecretFinding(
                id: "debug",
                ruleID: "stripe-access-token",
                kind: "Stripe Access Token",
                preview: "sk_liv…Q4",
                length: 32,
                providerID: providerID,
                locations: [],
                firstSeenAt: .now,
                status: .pending
            )]
        }
    #endif

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

    var nextRefreshAt: Date? {
        isEnabled && isAvailable && !providers.isEmpty ? nextScanAt : nil
    }

    private var conditions: SecretScanSchedule.Conditions {
        readConditions()
    }

    /// Called by the usage refresh scheduler after history has finished.
    func scanIfDue(now: Date = .now) async {
        guard !isTicking, isEnabled, isAvailable, now >= nextScanAt else { return }
        isTicking = true
        let generation = generation
        defer {
            isTicking = false
            isScanning = false
            let now = Date.now
            nextScanAt = providers.map { provider in
                if let retry = retries[provider.id] {
                    return max(
                        retry.at,
                        now.addingTimeInterval(SecretScanSchedule.tickInterval)
                    )
                }
                let due = state.lastScanAt[provider.id]?.addingTimeInterval(SecretScanSchedule.interval) ?? now
                return max(due, now.addingTimeInterval(SecretScanSchedule.tickInterval))
            }.min() ?? now.addingTimeInterval(SecretScanSchedule.interval)
        }
        for provider in providers {
            guard !Task.isCancelled, generation == self.generation else { return }
            if let retry = retries[provider.id], retry.at > .now {
                continue
            }
            let lastScanAt = state.lastScanAt[provider.id]
            let action = SecretScanSchedule.action(lastScanAt: lastScanAt, now: .now, conditions: conditions)
            guard action != .wait else { continue }
            let startedAt = Date.now
            isScanning = true
            do {
                // Checkpoints, rather than modification dates, decide what
                // is new. This also resumes partially completed first scans.
                let input = try await provider.source.input(since: nil)
                var matchesCount = 0
                var newCount = 0
                switch input {
                case let .files(urls):
                    let reader = SecretScanReader(urls: urls, checkpoints: state.checkpoints[provider.id] ?? [:])
                    while let batch = try await reader.next() {
                        try Task.checkCancellation()
                        guard generation == self.generation, store.isEnabled(provider.id) else { return }
                        guard SecretScanSchedule
                            .action(lastScanAt: lastScanAt, now: .now, conditions: conditions) != .wait
                        else { return }
                        let matches = try await batch.locate(runScan(.text(batch.data)))
                        try Task.checkCancellation()
                        guard generation == self.generation, store.isEnabled(provider.id) else { return }
                        let merged = SecretFinding.merge(
                            matches,
                            into: state.findings,
                            providerID: provider.id,
                            now: startedAt
                        )
                        var updated = state
                        updated.findings = merged.findings
                        for portion in batch.portions {
                            updated.checkpoints[provider.id, default: [:]][portion.url.path] = portion.checkpoint
                        }
                        // A failed write cannot acknowledge bytes we would
                        // otherwise forget to scan after a relaunch.
                        try stateStore.save(updated)
                        state = updated
                        matchesCount += matches.count
                        newCount += merged.new
                        if Date.now.timeIntervalSince(startedAt) >= 30 {
                            return
                        }
                    }
                    let paths = Set(urls.map(\.path))
                    state.checkpoints[provider.id] = state.checkpoints[provider.id]?.filter { paths.contains($0.key) }
                case let .text(data):
                    let matches = data.isEmpty ? [] : try await runScan(.text(data))
                    let merged = SecretFinding.merge(
                        matches,
                        into: state.findings,
                        providerID: provider.id,
                        now: startedAt
                    )
                    state.findings = merged.findings
                    matchesCount = matches.count
                    newCount = merged.new
                }
                try Task.checkCancellation()
                var updated = state
                updated.lastScanAt[provider.id] = startedAt
                try stateStore.save(updated)
                state = updated
                retries[provider.id] = nil
                failedProviderIDs.remove(provider.id)
                Analytics.capture(.secretScanCompleted(
                    provider: provider.id, kind: action == .full ? "full" : "hourly",
                    findings: matchesCount, new: newCount, seconds: Date.now.timeIntervalSince(startedAt)
                ))
            } catch is CancellationError {
                return
            } catch {
                let failures = min((retries[provider.id]?.failures ?? 0) + 1, 5)
                retries[provider.id] = (
                    failures,
                    Date.now.addingTimeInterval(min(300 * pow(2, Double(failures - 1)), 3600))
                )
                failedProviderIDs.insert(provider.id)
            }
            isScanning = false
        }
    }

    private func runScan(_ input: SecretScanInput) async throws -> [SecretMatch] {
        let scan = scan
        let task = Task(priority: .utility) { try await scan(input) }
        activeScan = task
        defer { activeScan = nil }
        return try await withTaskCancellationHandler {
            let matches = try await task.value
            try Task.checkCancellation()
            return matches
        } onCancel: {
            task.cancel()
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
        guard let index = state.findings.firstIndex(where: { $0.id == id }) else {
            testFindings.removeAll { $0.id == id }
            return nil
        }
        state.findings[index].status = status
        try? stateStore.save(state)
        return state.findings[index]
    }
}
