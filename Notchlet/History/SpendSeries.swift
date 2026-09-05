import Foundation

/// The last 30 days of cost. A day before coverage has no cost, so the line
/// breaks there instead of drawing a zero that was never measured.
nonisolated struct SpendSeries: Equatable, Sendable {
    static let days = 30

    struct Point: Equatable, Sendable {
        let day: DayKey
        let cost: Double?
    }

    let points: [Point]
    let maxCost: Double

    init(today: DayKey, calendar: Calendar, costs: [DayKey: Double], coverageStart: DayKey?) {
        let start = today.advanced(by: 1 - Self.days, calendar: calendar)
        points = start.days(through: today, calendar: calendar).map { day in
            let known = coverageStart.map { day >= $0 } ?? true
            return Point(day: day, cost: known ? costs[day] ?? 0 : nil)
        }
        maxCost = points.compactMap(\.cost).max() ?? 0
    }
}
