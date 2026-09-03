import Foundation

/// The 53-week grid behind the activity graph: one cell per day, the last
/// column being the current week, laid out the way GitHub does it. Pure so
/// the day-to-cell mapping and the levels stay testable.
///
/// Levels are quartiles of the days that had any usage, so one heavy month
/// does not flatten the rest of the year into the darkest shade. Days
/// before the archive's coverage are unknown, not quiet, and get their own
/// fill.
nonisolated struct ActivityGrid: Equatable, Sendable {
    static let weeks = 53
    static let rows = 7

    enum Fill: Equatable, Sendable {
        case unknown
        case empty
        /// 1 (lightest use) through 4 (heaviest).
        case level(Int)
    }

    struct Cell: Equatable, Sendable {
        let day: DayKey
        let column: Int
        let row: Int
        let tokens: Int
        let fill: Fill
    }

    struct MonthLabel: Equatable, Sendable {
        let column: Int
        let text: String
    }

    let start: DayKey
    let end: DayKey
    let cells: [Cell]
    let monthLabels: [MonthLabel]

    init(today: DayKey, calendar: Calendar, tokens: [DayKey: Int], coverageStart: DayKey?) {
        // Back to the first day of the week 52 weeks before this one.
        let weekday = calendar.component(.weekday, from: today.start(in: calendar))
        let daysIntoWeek = (weekday - calendar.firstWeekday + 7) % 7
        let start = today.advanced(by: -(daysIntoWeek + (Self.weeks - 1) * 7), calendar: calendar)
        self.start = start
        end = today

        // Only days the grid draws set its levels.
        let thresholds = Self.quartiles(of: tokens.compactMap { day, count in
            day >= start && day <= today && count > 0 && (coverageStart.map { day >= $0 } ?? true) ? count : nil
        })
        // Month names in English like the rest of the pane, whatever the
        // calendar's locale.
        var labelCalendar = calendar
        labelCalendar.locale = Locale(identifier: "en_US")
        var cells: [Cell] = []
        var labels: [MonthLabel] = []
        var previousMonth: Int?
        var lastLabelColumn = -3
        for (index, day) in start.days(through: today, calendar: calendar).enumerated() {
            let column = index / 7
            let row = index % 7
            let count = tokens[day] ?? 0
            let fill: Fill = if let coverageStart, day < coverageStart {
                .unknown
            } else if count == 0 {
                .empty
            } else {
                .level(1 + thresholds.filter { count >= $0 }.count)
            }
            cells.append(Cell(day: day, column: column, row: row, tokens: count, fill: fill))
            // A month is labeled over the first week that starts in it, if
            // the previous label left it three columns of room.
            if row == 0, day.month != previousMonth {
                previousMonth = day.month
                if column - lastLabelColumn >= 3, column <= Self.weeks - 3 {
                    labels.append(MonthLabel(column: column, text: labelCalendar.shortMonthSymbols[day.month - 1]))
                    lastLabelColumn = column
                }
            }
        }
        self.cells = cells
        monthLabels = labels
    }

    func cell(atColumn column: Int, row: Int) -> Cell? {
        guard (0 ..< Self.weeks).contains(column), (0 ..< Self.rows).contains(row) else { return nil }
        let index = column * 7 + row
        return index < cells.count ? cells[index] : nil
    }

    /// The three cut points between the four levels.
    static func quartiles(of values: [Int]) -> [Int] {
        guard !values.isEmpty else { return [] }
        let sorted = values.sorted()
        return [0.25, 0.5, 0.75].map { sorted[min(Int(Double(sorted.count) * $0), sorted.count - 1)] }
    }
}
