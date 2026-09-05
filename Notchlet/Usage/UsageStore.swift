import Foundation
import Observation

/// The latest snapshot per provider and the refresh loop: slow while the
/// panel is closed, every 60s while open, per-provider backoff on a rate
/// limit. A failing provider keeps its previous snapshot.
@Observable
final class UsageStore {
    enum ProviderState: Equatable {
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
    /// Every successful fetch with the snapshot it replaced; the alerts
    /// hang off this.
    var snapshotObserver: ((_ providerID: String, _ previous: UsageSnapshot?, _ current: UsageSnapshot) -> Void)?

    init(providers: [any UsageProvider], defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = providers.map { Entry(provider: $0, snapshot: nil) }
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
        reschedule()
    }

    /// Cooldowns included: the user just changed how the provider signs in.
    /// A provider that is off is fetched once anyway, so its settings page
    /// can say whether the login works.
    func refreshNow(_ providerID: String) {
        guard let index = entries.firstIndex(where: { $0.id == providerID }) else { return }
        entries[index].schedule = RefreshSchedule()
        if isEnabled(providerID) {
            reschedule()
        } else {
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
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await refreshDueProviders()
                guard !Task.isCancelled, let delay = timeUntilNextDue() else { return }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private var pollInterval: TimeInterval {
        if isPanelOpen {
            return Self.openInterval
        }
        let minutes = defaults.integer(forKey: Self.intervalDefaultsKey)
        return TimeInterval(Self.intervalChoicesMinutes.contains(minutes) ? minutes : 10) * 60
    }

    private func timeUntilNextDue() -> TimeInterval? {
        let interval = pollInterval
        let nextDue = entries.filter { isEnabled($0.id) }
            .map { $0.schedule.nextDue(interval: interval) }.min()
        return nextDue.map { max($0.timeIntervalSinceNow, 1) }
    }

    private func refreshDueProviders() async {
        let interval = pollInterval
        let now = Date.now
        let due = entries.indices.filter {
            isEnabled(entries[$0].id) && entries[$0].schedule.nextDue(interval: interval) <= now
        }
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
            activeProviders: entries.filter { isEnabled($0.id) && $0.state == .ok }.map(\.id),
            planTiers: entries.reduce(into: [:]) { tiers, entry in
                if let tier = entry.snapshot?.planTier {
                    tiers[entry.id] = tier
                }
            }
        )
    }

    private enum FetchOutcome {
        case success(UsageSnapshot)
        case notAvailable(AuthProblem)
        case rateLimited(retryAfter: TimeInterval?)
        case failed
        /// Our own reschedule, not a provider fault.
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
    }

    /// Bucketed usage pressure per provider, sent with the daily heartbeat.
    /// The longest window (weekly or monthly) is the stable "how constrained
    /// is this user" signal; the 5-hour one swings too much to sample daily.
    var usagePressure: [String: String] {
        entries.reduce(into: [:]) { pressure, entry in
            guard let window = entry.snapshot?.windows.max(by: { $0.duration < $1.duration })
            else { return }
            pressure[entry.id] = Self.pressureBucket(window.usedFraction)
        }
    }

    static func pressureBucket(_ usedFraction: Double) -> String {
        switch usedFraction {
        case ..<0.25: "0-25"
        case ..<0.5: "25-50"
        case ..<0.75: "50-75"
        default: "75-100"
        }
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
