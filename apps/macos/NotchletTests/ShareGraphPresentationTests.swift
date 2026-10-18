import Foundation
@testable import Notchlet
import Testing

struct ShareGraphPresentationTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let today = TestSupport.day("2026-01-08")

    @Test func remembersChoicesAcrossPeriodsAndToday() {
        var options = ShareOptions()
        options.graph = .spend
        options.period = .year
        #expect(options.graph == .calendar)
        options.graph = .none
        options.period = .week
        #expect(options.graph == .activity)
        options.period = .today
        options.graph = .calendar
        #expect(options.graph == .none)
        options.period = .month
        #expect(options.graph == .spend)
        var restored = ShareOptions()
        restored.restoreGraphs(options.savedGraphs, legacy: nil)
        #expect(restored.graph == .spend)
        restored.period = .year
        #expect(restored.graph == .none)
    }

    @Test(arguments: ShareGraph.allCases)
    func migratesLegacyChoice(legacy: ShareGraph) {
        var options = ShareOptions()
        options.restoreGraphs([:], legacy: legacy)
        #expect(options.graph == legacy)
        options.period = .year
        #expect(options.graph == (legacy == .activity ? .calendar : legacy))
    }

    @Test func savedChoiceWinsOverLegacy() {
        var options = ShareOptions(period: .year)
        options.restoreGraphs(["year": "activity"], legacy: .none)
        #expect(options.graph == .activity)
    }

    @Test func weeklyGroupsPartitionTheCoveredDatesAcrossYearBoundary() {
        let start = TestSupport.day("2025-11-28")
        let presentation = ShareGraphPresentation(
            options: ShareOptions(period: .year, graph: .activity), coverageStart: start,
            today: today, calendar: calendar, hasUsage: true, hasCost: true
        )
        let groups = presentation.groups(calendar: calendar)
        #expect(presentation.weekly)
        #expect(groups.first?.lowerBound == start)
        #expect(groups.last?.upperBound == today)
        let dates = groups.flatMap { $0.lowerBound.days(through: $0.upperBound, calendar: calendar) }
        #expect(dates == start.days(through: today, calendar: calendar))
        #expect(groups.dropFirst().allSatisfy {
            calendar.component(.weekday, from: $0.lowerBound.start(in: calendar)) == calendar.firstWeekday
        })
    }

    @Test func shortYearUsesDailyValuesAndUnavailableGraphsDoNotChangePreference() {
        let options = ShareOptions(period: .year, graph: .spend)
        let presentation = ShareGraphPresentation(
            options: options, coverageStart: today.advanced(by: -29, calendar: calendar),
            today: today, calendar: calendar, hasUsage: true, hasCost: false
        )
        #expect(!presentation.weekly)
        #expect(presentation.graph == .none)
        #expect(options.graph == .spend)
        let week = ShareGraphPresentation(
            options: ShareOptions(period: .week, graph: .calendar), coverageStart: nil,
            today: today, calendar: calendar, hasUsage: true, hasCost: true
        )
        #expect(week.graph == .none)
    }
}
