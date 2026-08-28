import Foundation
import Observation

/// Holds the latest snapshot for every configured provider and refreshes them
/// on demand. Periodic refresh (a timer) is on the roadmap.
@Observable
final class UsageStore {
    struct Entry: Identifiable {
        let provider: any UsageProvider
        var snapshot: UsageSnapshot?

        var id: String { provider.id }
    }

    private(set) var entries: [Entry]

    init(providers: [any UsageProvider]) {
        entries = providers.map { Entry(provider: $0, snapshot: nil) }
    }

    /// Refreshes every provider. A failing provider keeps its previous
    /// snapshot; surfacing errors in the UI comes later.
    func refresh() async {
        for index in entries.indices {
            do {
                entries[index].snapshot = try await entries[index].provider.fetchUsage()
            } catch {
                // Intentionally silent for now.
            }
        }
    }
}
