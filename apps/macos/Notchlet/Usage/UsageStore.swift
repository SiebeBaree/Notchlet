import Foundation
import Observation

/// The latest snapshot per provider and the refresh loop: slow while the
/// panel is closed, every 60s while open, per-provider backoff on a rate
/// limit. A failing provider keeps its previous snapshot. Snapshots and
/// schedules are saved, so a relaunch or an update shows the last numbers
/// at once and does not fetch before they are due.
@Observable
final class UsageStore {
    enum ProviderState: Codable, Equatable {
        case ok
        case notAvailable(AuthProblem)
        case rateLimited
        case error

        var analyticsName: String {
            switch self {
            case .ok: "ok"
            case .notAvailable: "not_available"
            case .rateLimited: "rate_limited"
            case .error: "error"
            }
        }
    }

    struct Entry: Identifiable {
        let provider: any UsageProvider
        var snapshot: UsageSnapshot?
        var state: ProviderState?
        var schedule = RefreshSchedule()

        var id: String { provider.id }
    }

    /// Three summary gauges fit side by side in the expanded panel.
    static let maxActiveProviders = 3

    /// Closed-panel poll interval in minutes; the settings picker writes the
    /// same key. Unknown values fall back to 10.
    static let intervalDefaultsKey = "refreshIntervalMinutes"
    static let intervalChoicesMinutes = [3, 5, 10, 15, 30]

    /// Poll interval while the panel is open, and the age past which opening
    /// it triggers an immediate refetch.
    private static let openInterval: TimeInterval = 60

    private let defaults: UserDefaults
    private(set) var entries: [Entry]
    /// Unset means on when the CLI is installed, up to the cap; a stored
    /// choice always wins. Disabled providers keep their entry but are
    /// neither polled nor shown.
    private var providerEnabled: [String: Bool]
    private var isPanelOpen = false
    private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var cycle: Task<Void, Never>?
    @ObservationIgnored private var maintenance: Task<Void, Never>?
    private var isSuspended = false
    var nextBackgroundRefresh: (() -> Date?)?
    var backgroundRefresh: (() async -> Void)?
    /// Every successful fetch with the snapshot it replaced; the alerts
    /// hang off this.
    var snapshotObserver: ((_ providerID: String, _ previous: UsageSnapshot?, _ current: UsageSnapshot) -> Void)?

    init(providers: [any UsageProvider], defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = providers.map { provider in
            let saved = defaults.data(forKey: Self.savedDefaultsKey(provider.id))
                .flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
            return Entry(
                provider: provider,
                snapshot: saved?.snapshot,
                state: saved?.state,
                schedule: saved?.schedule ?? RefreshSchedule()
            )
        }
        // Stored choices first, then installed CLIs fill the remaining slots
        // in registration order.
        var enabled: [String: Bool] = [:]
        for provider in providers {
            enabled[provider.id] = defaults.object(forKey: Self.enabledDefaultsKey(provider.id)) as? Bool
        }
        var openSlots = Self.maxActiveProviders - enabled.values.filter { $0 == true }.count
        for provider in providers where enabled[provider.id] == nil {
            let on = provider.isInstalled && openSlots > 0
            enabled[provider.id] = on
            if on {
                openSlots -= 1
            }
        }
        providerEnabled = enabled
    }

    static func enabledDefaultsKey(_ providerID: String) -> String {
        "providerEnabled.\(providerID)"
    }

    static func savedDefaultsKey(_ providerID: String) -> String {
        "usageSnapshot.\(providerID)"
    }

    private struct Saved: Codable {
        var snapshot: UsageSnapshot?
        var state: ProviderState?
        var schedule: RefreshSchedule
    }

    private func save(at index: Int) {
        let entry = entries[index]
        let saved = Saved(snapshot: entry.snapshot, state: entry.state, schedule: entry.schedule)
        defaults.set(try? JSONEncoder().encode(saved), forKey: Self.savedDefaultsKey(entry.id))
    }

    func isEnabled(_ providerID: String) -> Bool {
        providerEnabled[providerID] ?? true
    }

    var canEnableMore: Bool {
        entries.filter { isEnabled($0.id) }.count < Self.maxActiveProviders
    }

    /// Ignores a request past the cap; the toggle is disabled then, so this
    /// only guards a race.
    func setEnabled(_ providerID: String, _ enabled: Bool) {
        if enabled, !isEnabled(providerID), !canEnableMore {
            return
        }
        providerEnabled[providerID] = enabled
        defaults.set(enabled, forKey: Self.enabledDefaultsKey(providerID))
        if !enabled {
            cycle?.cancel()
            maintenance?.cancel()
        }
        reschedule()
    }

    /// Error backoff included, not a rate limit: the user just changed how
    /// the provider signs in, but retrying into a rate limit only extends
    /// it. A provider that is off is fetched once anyway, outside a rate
    /// limit, so its settings page can say whether the login works.
    func refreshNow(_ providerID: String) {
        guard let index = entries.firstIndex(where: { $0.id == providerID }) else { return }
        entries[index].provider.retryCredentialAccess()
        entries[index].schedule.retryNow()
        if isEnabled(providerID) {
            reschedule()
        } else if nextDue(entries[index]) <= .now {
            Task { [weak self] in
                await self?.fetch([index], now: .now)
            }
        }
    }

    /// Opening shrinks the interval to `openInterval`, which makes anything
    /// older than that due now. Backoff still holds.
    func setPanelOpen(_ open: Bool) {
        guard open != isPanelOpen else { return }
        isPanelOpen = open
        reschedule()
    }

    /// Restarts the loop so a changed input (interval setting, wake from
    /// sleep) takes effect now.
    func reschedule() {
        refreshTask?.cancel()
        guard !isSuspended else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await refreshCycle()
                guard !Task.isCancelled else { return }
                startMaintenanceIfDue()
                guard let delay = timeUntilNextDue() else { return }
                try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(min(delay * 0.1, 30)))
            }
        }
    }

    /// Rescheduling changes the next wakeup, not the ownership of work
    /// already in flight. Sleep and disabling a provider cancel that work.
    private func refreshCycle() async {
        if cycle == nil {
            cycle = Task(priority: .utility) { [weak self] in
                guard let self else { return }
                defer { cycle = nil }
                await refreshDueProviders()
            }
        }
        await cycle?.value
    }

    /// History and scanning stay serial, but a slow helper must not hold
    /// up usage refreshes. Completion updates the same scheduler's deadline.
    private func startMaintenanceIfDue() {
        guard maintenance == nil, let due = nextBackgroundRefresh?(), due <= .now,
              let backgroundRefresh else { return }
        maintenance = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                maintenance = nil
                reschedule()
            }
            await backgroundRefresh()
        }
    }

    func suspend() {
        isSuspended = true
        refreshTask?.cancel()
        cycle?.cancel()
        maintenance?.cancel()
    }

    func resume() {
        isSuspended = false
        reschedule()
    }

    func connectionRestored() {
        for index in entries.indices {
            entries[index].schedule.connectionRestored()
        }
        reschedule()
    }

    private var pollInterval: TimeInterval {
        if isPanelOpen {
            return Self.openInterval
        }
        let minutes = defaults.integer(forKey: Self.intervalDefaultsKey)
        return TimeInterval(Self.intervalChoicesMinutes.contains(minutes) ? minutes : 10) * 60
    }

    private func nextDue(_ entry: Entry) -> Date {
        entry.schedule.nextDue(interval: pollInterval, floor: entry.provider.minimumInterval)
    }

    private func timeUntilNextDue() -> TimeInterval? {
        var due = entries.filter { isEnabled($0.id) }.map(nextDue)
        if maintenance == nil, let background = nextBackgroundRefresh?() {
            due.append(background)
        }
        let soonest = due.min()
        return soonest.map { max($0.timeIntervalSinceNow, 1) }
    }

    private func refreshDueProviders() async {
        let now = Date.now
        let due = entries.indices.filter { isEnabled(entries[$0].id) && nextDue(entries[$0]) <= now }
        guard !due.isEmpty else { return }
        await fetch(due, now: now)
    }

    private func fetch(_ indices: [Int], now: Date) async {
        for index in indices {
            entries[index].schedule.recordAttempt(now: now)
        }
        await withTaskGroup(of: (Int, FetchOutcome).self) { group in
            for index in indices {
                let provider = entries[index].provider
                group.addTask {
                    do {
                        return try await (index, .success(provider.fetchUsage()))
                    } catch let ProviderError.notAvailable(problem) {
                        return (index, .notAvailable(problem))
                    } catch let ProviderError.rateLimited(retryAfter) {
                        return (index, .rateLimited(retryAfter: retryAfter))
                    } catch is CancellationError {
                        return (index, .cancelled)
                    } catch let error as URLError where error.code == .cancelled {
                        return (index, .cancelled)
                    } catch {
                        return (index, .failed)
                    }
                }
            }
            for await (index, outcome) in group {
                apply(outcome, at: index)
            }
        }
        Analytics.updateProviderContext(
            activeProviders: entries.filter { isEnabled($0.id) && $0.state == .ok }.map(\.id)
        )
    }

    private enum FetchOutcome {
        case success(UsageSnapshot)
        case notAvailable(AuthProblem)
        case rateLimited(retryAfter: TimeInterval?)
        case failed
        /// Sleep or a disabled provider, not a provider fault.
        case cancelled
    }

    private func apply(_ outcome: FetchOutcome, at index: Int) {
        switch outcome {
        case let .success(snapshot):
            let previous = entries[index].snapshot
            entries[index].snapshot = snapshot
            snapshotObserver?(entries[index].id, previous, snapshot)
            entries[index].schedule.recordSuccess()
            transition(at: index, to: .ok)
        case let .notAvailable(problem):
            // Nothing to back off from.
            entries[index].schedule.recordSuccess()
            transition(at: index, to: .notAvailable(problem))
        case let .rateLimited(retryAfter):
            entries[index].schedule.recordRateLimit(retryAfter: retryAfter)
            transition(at: index, to: .rateLimited)
        case .failed:
            entries[index].schedule.recordError()
            transition(at: index, to: .error)
        case .cancelled:
            // No state change and no backoff; the recorded attempt still
            // holds the 30s spacing.
            break
        }
        save(at: index)
    }

    /// Only transitions are analytics events, never every refresh.
    private func transition(at index: Int, to newState: ProviderState) {
        let oldState = entries[index].state
        entries[index].state = newState
        if let oldState, oldState.analyticsName != newState.analyticsName {
            Analytics.capture(.providerStateChanged(provider: entries[index].id, state: newState))
        }
    }
}
