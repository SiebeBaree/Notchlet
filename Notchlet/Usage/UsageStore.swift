import Foundation
import Observation

/// Holds the latest snapshot for every configured provider and refreshes them
/// on a fixed interval.
@Observable
final class UsageStore {
    /// Whether a provider's last refresh worked, found no usable login, or
    /// failed outright.
    enum ProviderState: String {
        case ok
        case notAvailable = "not_available"
        case error
    }

    struct Entry: Identifiable {
        let provider: any UsageProvider
        var snapshot: UsageSnapshot?
        var state: ProviderState?

        var id: String { provider.id }
    }

    private(set) var entries: [Entry]
    private var refreshTask: Task<Void, Never>?

    init(providers: [any UsageProvider]) {
        entries = providers.map { Entry(provider: $0, snapshot: nil) }
    }

    /// Refreshes now and keeps refreshing on an interval. The loop ends on
    /// its own once the store goes away.
    func startRefreshing(every interval: Duration = .seconds(60)) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Refreshes every provider. A failing provider keeps its previous
    /// snapshot; surfacing errors in the UI comes later.
    func refresh() async {
        for index in entries.indices {
            do {
                entries[index].snapshot = try await entries[index].provider.fetchUsage()
                transition(at: index, to: .ok)
            } catch UsageProviderError.notAvailable {
                transition(at: index, to: .notAvailable)
            } catch {
                transition(at: index, to: .error)
            }
        }
        Analytics.updateProviderContext(
            activeProviders: entries.filter { $0.state == .ok }.map(\.id),
            planTiers: entries.reduce(into: [:]) { tiers, entry in
                if let tier = entry.snapshot?.planTier {
                    tiers[entry.id] = tier
                }
            }
        )
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
