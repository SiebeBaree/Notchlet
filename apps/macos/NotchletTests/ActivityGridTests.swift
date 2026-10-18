import Foundation
@testable import Notchlet
import Testing

struct ActivityGridTests {
    /// Weeks start on Monday, as they do for most of the world.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// A Thursday.
    private let today = TestSupport.day("2026-09-03")

    @Test func startsOnTheFirstDayOfTheWeekFiftyTwoWeeksBack() {
        let grid = ActivityGrid(today: today, calendar: calendar, tokens: [:], coverageStart: nil)
        #expect(grid.start.string == "2025-09-01")
        #expect(grid.cells.count == 52 * 7 + 4)
        #expect(grid.cells.first?.column == 0)
        #expect(grid.cells.first?.row == 0)
        #expect(grid.cells.last?.day == today)
        #expect(grid.cells.last?.column == 52)
        #expect(grid.cells.last?.row == 3)
    }

    @Test func cellsMapBackFromColumnAndRow() {
        let grid = ActivityGrid(today: today, calendar: calendar, tokens: [:], coverageStart: nil)
        #expect(grid.cell(atColumn: 0, row: 0)?.day.string == "2025-09-01")
        #expect(grid.cell(atColumn: 1, row: 2)?.day.string == "2025-09-10")
        #expect(grid.cell(atColumn: 52, row: 3)?.day == today)
        #expect(grid.cell(atColumn: 52, row: 4) == nil)
        #expect(grid.cell(atColumn: 53, row: 0) == nil)
        #expect(grid.cell(atColumn: -1, row: 0) == nil)
    }

    @Test func levelsAreQuartilesOfTheDaysWithUsage() {
        var tokens: [DayKey: Int] = [:]
        for (offset, count) in [10, 20, 30, 40, 50, 60, 70, 80].enumerated() {
            tokens[today.advanced(by: -offset, calendar: calendar)] = count
        }
        let grid = ActivityGrid(today: today, calendar: calendar, tokens: tokens, coverageStart: nil)
        let fills = (0 ..< 8).map { grid.cell(for: today.advanced(by: -$0, calendar: calendar))?.fill }

        #expect(fills == [.level(1), .level(1), .level(2), .level(2), .level(3), .level(3), .level(4), .level(4)])
        #expect(grid.cell(for: today.advanced(by: -9, calendar: calendar))?.fill == .empty)
    }

    @Test func daysOutsideTheGridDoNotSetItsLevels() {
        let inside = today.advanced(by: -3, calendar: calendar)
        let before = TestSupport.day("2025-08-01")
        let grid = ActivityGrid(
            today: today,
            calendar: calendar,
            tokens: [inside: 1, before: 1_000_000],
            coverageStart: nil
        )
        #expect(grid.cell(for: inside)?.fill == .level(4))
    }

    @Test func daysBeforeCoverageAreUnknownNotEmpty() {
        let coverage = TestSupport.day("2026-07-24")
        let grid = ActivityGrid(today: today, calendar: calendar, tokens: [coverage: 5], coverageStart: coverage)
        #expect(grid.cell(for: coverage.advanced(by: -1, calendar: calendar))?.fill == .unknown)
        #expect(grid.cell(for: coverage)?.fill == .level(4))
        #expect(grid.cell(for: today)?.fill == .empty)
    }

    @Test func monthLabelsLeaveRoomForEachOther() {
        let grid = ActivityGrid(today: today, calendar: calendar, tokens: [:], coverageStart: nil)
        let labels = grid.monthLabels.map { "\($0.column):\($0.text)" }
        // September 2025 starts in column 0; a partial first month would
        // have yielded to the next one.
        #expect(labels.first == "0:Sep")
        #expect(grid.monthLabels.count == 12)
        for (a, b) in zip(grid.monthLabels, grid.monthLabels.dropFirst()) {
            #expect(b.column - a.column >= 3)
        }
    }
}

private extension ActivityGrid {
    func cell(for day: DayKey) -> Cell? {
        cells.first { $0.day == day }
    }
}
