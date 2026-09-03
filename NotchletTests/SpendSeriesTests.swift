import Foundation
@testable import Notchlet
import Testing

struct SpendSeriesTests {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let today = TestSupport.day("2026-09-03")

    @Test func thirtyPointsEndingToday() {
        let series = SpendSeries(today: today, calendar: utc, costs: [today: 4.2], coverageStart: nil)
        #expect(series.points.count == 30)
        #expect(series.points.first?.day.string == "2026-08-05")
        #expect(series.points.last?.day == today)
        #expect(series.points.last?.cost == 4.2)
        #expect(series.points.first?.cost == 0)
        #expect(series.maxCost == 4.2)
    }

    @Test func daysBeforeCoverageHaveNoPoint() {
        let coverage = TestSupport.day("2026-08-20")
        let series = SpendSeries(today: today, calendar: utc, costs: [coverage: 1], coverageStart: coverage)
        #expect(series.points.first?.cost == nil)
        #expect(series.points.first { $0.day == coverage }?.cost == 1)
        #expect(series.points.filter { $0.cost == nil }.count == 15)
    }
}
