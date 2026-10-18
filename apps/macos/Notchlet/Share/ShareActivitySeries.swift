import Foundation

/// Only the days included in the image, so unavailable months take no space.
nonisolated struct ShareActivitySeries: Equatable, Sendable {
    struct Point: Equatable, Sendable {
        let day: DayKey
        let tokens: Int
        let level: Int
    }

    let points: [Point]
    let maxTokens: Int
    let weekly: Bool
    let end: DayKey

    init(groups: [ClosedRange<DayKey>], ledger: UsageLedger, weekly: Bool, end: DayKey) {
        self.weekly = weekly
        self.end = end
        let counts = groups.map { ledger.summary($0).tokens }
        let thresholds = ActivityGrid.quartiles(of: counts.filter { $0 > 0 })
        points = zip(groups, counts).map { group, count in
            Point(
                day: group.lowerBound,
                tokens: count,
                level: count > 0 ? 1 + thresholds.filter { count >= $0 }.count : 0
            )
        }
        maxTokens = counts.max() ?? 0
    }
}
