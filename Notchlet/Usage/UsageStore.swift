import Foundation
import Observation

/// Holds the latest snapshot for every configured provider and schedules
/// refreshes: a slow heartbeat while the panel is closed, a fast one while it
/// is open (which also refetches stale data the moment the user looks), and
/// per-provider backoff when an endpoint rate limits us. A failing provider
/// keeps its previous snapshot; the panel labels its age instead.
@Observable
final class UsageStore {
    /// Whether a provider's last refresh worked, found no usable login,
    /// hit a rate limit, or failed outright.
    enum ProviderState: String {
        case ok
        case notAvailable = "not_available"
        case rateLimited = "rate_limited"
        case error
    }

    struct Entry: Identifiable {
        let provider: any UsageProvider
        var snapshot: UsageSnapshot?
        var state: ProviderState?
        /// Why the last refresh found no usable login, while `state` is
        /// `notAvailable`. Drives the status line in the provider's settings.
        var authProblem: AuthProblem?
        var schedule = RefreshSchedule()

        var id: String { provider.id }
    }

    /// How many providers can be on at once. The expanded panel has room
    /// for three summary gauges side by side; more would crowd the notch.
    static let maxActiveProviders = 3

    /// Closed-panel poll interval in minutes; the settings picker writes the
    /// same key. Unset or out-of-catalog values fall back to 10.
    static let intervalDefaultsKey = "refreshIntervalMinutes"
    static let intervalChoicesMinutes = [3, 5, 10, 15, 30]

    /// Poll interval while the panel is open, and the age past which opening
    /// it triggers an immediate refetch.
    private static let openInterval: TimeInterval = 60

    private(set) var entries: [Entry]
    /// Per-provider visibility from settings. Unset means "on when the CLI
    /// is installed", capped at `maxActiveProviders`, so a fresh launch
    /// shows the agents present on this machine; a stored user choice always
    /// wins. Disabled providers keep their entry (and last snapshot) but are
    /// neither polled nor shown.
    private var providerEnabled: [String: Bool]
    private var isPanelOpen = false
    private var refreshTask: Task<Void, Never>?

    init(providers: [any UsageProvider]) {
        entries = providers.map { Entry(provider: $0, snapshot: nil) }
        // Stored choices first, then installed CLIs fill the remaining slots
        // in registration order. A fresh install with four CLIs shows the
        // first three and leaves the fourth one toggle away.
        var enabled: [String: Bool] = [:]
        for provider in providers {
            enabled[provider.id] = UserDefaults.standard.object(forKey: Self.enabledDefaultsKey(provider.id)) as? Bool
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

    /// Whether another provider can be switched on without passing the cap.
    var canEnableMore: Bool {
        entries.filter { isEnabled($0.id) }.count < Self.maxActiveProviders
    }

    /// Ignores a request that would pass the cap; the settings toggle is
    /// disabled in that state, so this only guards against races.
    func setEnabled(_ providerID: String, _ enabled: Bool) {
        if enabled, !isEnabled(providerID), !canEnableMore {
            return
        }
        providerEnabled[providerID] = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledDefaultsKey(providerID))
        // Re-enabling fetches right away if the data is due; disabling just
        // drops the provider from the loop.
        reschedule()
    }

    /// Fetches now and keeps the scheduling loop alive for the lifetime of
    /// the store.
    func startRefreshing() {
        reschedule()
    }

    /// Fetches one provider right away, cooldowns included: the user just
    /// changed how it signs in, so whatever it last knew is moot.
    func refreshNow(_ providerID: String) {
        guard let index = entries.firstIndex(where: { $0.id == providerID }) else { return }
        entries[index].schedule = RefreshSchedule()
        reschedule()
    }

    /// Panel visibility drives the cadence. Opening shrinks the interval to
    /// `openInterval`, which makes any provider older than that due
    /// immediately, so the user sees fresh numbers at the moment they look.
    /// Backoff cooldowns still hold: a rate-limited provider is not poked.
    func setPanelOpen(_ open: Bool) {
        guard open != isPanelOpen else { return }
        isPanelOpen = open
        reschedule()
    }

    /// Restarts the scheduling loop so a changed input (interval setting,
    /// wake from sleep) takes effect now: anything overdue fetches right
    /// away, everything else just gets its next due time recomputed.
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
        let minutes = UserDefaults.standard.integer(forKey: Self.intervalDefaultsKey)
        return TimeInterval(Self.intervalChoicesMinutes.contains(minutes) ? minutes : 10) * 60
    }

    private func timeUntilNextDue() -> TimeInterval? {
        let interval = pollInterval
        let nextDue = entries.filter { isEnabled($0.id) }
            .map { $0.schedule.nextDue(interval: interval) }.min()
        return nextDue.map { max($0.timeIntervalSinceNow, 1) }
    }

    /// Fetches every provider that has come due, concurrently so one slow
    /// endpoint doesn't hold up the others.
    private func refreshDueProviders() async {
        let interval = pollInterval
        let now = Date.now
        let due = entries.indices.filter {
            isEnabled(entries[$0].id) && entries[$0].schedule.nextDue(interval: interval) <= now
        }
        guard !due.isEmpty else { return }

        for index in due {
            entries[index].schedule.recordAttempt(now: now)
        }
        await withTaskGroup(of: (Int, FetchOutcome).self) { group in
            for index in due {
                let provider = entries[index].provider
                group.addTask {
                    do {
                        return try await (index, .success(provider.fetchUsage()))
                    } catch let UsageProviderError.notAvailable(problem) {
                        return (index, .notAvailable(problem))
                    } catch let UsageProviderError.rateLimited(retryAfter) {
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
        /// The refresh loop was restarted mid-flight, not a provider fault.
        case cancelled
    }

    private func apply(_ outcome: FetchOutcome, at index: Int) {
        switch outcome {
        case let .success(snapshot):
            entries[index].snapshot = snapshot
            entries[index].authProblem = nil
            entries[index].schedule.recordSuccess()
            transition(at: index, to: .ok)
        case let .notAvailable(problem):
            // A local credentials check or a plain rejection, so nothing to
            // back off from.
            entries[index].authProblem = problem
            entries[index].schedule.recordSuccess()
            transition(at: index, to: .notAvailable)
        case let .rateLimited(retryAfter):
            entries[index].schedule.recordRateLimit(retryAfter: retryAfter)
            transition(at: index, to: .rateLimited)
        case .failed:
            entries[index].schedule.recordError()
            transition(at: index, to: .error)
        case .cancelled:
            // We cancelled this fetch ourselves by rescheduling, so the
            // provider learns nothing: no state change and no backoff. The
            // attempt recorded before the fetch still holds the 30s spacing.
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

    /// Records the new state and reports the change. Only transitions are
    /// analytics events, never the steady state of every refresh.
    private func transition(at index: Int, to newState: ProviderState) {
        let oldState = entries[index].state
        entries[index].state = newState
        if let oldState, oldState != newState {
            Analytics.capture(.providerStateChanged(provider: entries[index].id, state: newState))
        }
    }
}
