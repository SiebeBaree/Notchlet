import Foundation

/// One decision for the editor and the exported image, including fallbacks.
nonisolated struct ShareGraphPresentation: Equatable, Sendable {
    let graph: ShareGraph
    let span: ClosedRange<DayKey>
    let days: Int
    let weekly: Bool
    let detail: String

    init(options: ShareOptions, coverageStart: DayKey?, today: DayKey, calendar: Calendar,
         hasUsage: Bool, hasCost: Bool)
    {
        let selected = options.period.span(endingOn: today, calendar: calendar)
        span = min(today, max(selected.lowerBound, coverageStart ?? selected.lowerBound)) ... today
        days = span.lowerBound.days(through: today, calendar: calendar).count
        weekly = options.period == .year && days > 30
        if !hasUsage {
            graph = .none
            detail = "No usage in this period"
        } else if days < 2 {
            graph = .none
            detail = "Graphs need more than one day"
        } else if options.graph == .calendar, options.period == .week {
            graph = .none
            detail = "Calendar is available for 30 days and 12 months"
        } else if options.graph == .spend, !hasCost {
            graph = .none
            detail = "Nothing priced in this period"
        } else {
            graph = options.graph
            detail = switch graph {
            case .activity: weekly ? "Tokens per week" : "Tokens per day"
            case .spend: weekly ? "Cost per week" : "Cost per day"
            case .calendar: "One square per day"
            case .none: "Just the numbers"
            }
        }
    }

    func groups(calendar: Calendar) -> [ClosedRange<DayKey>] {
        let dates = span.lowerBound.days(through: span.upperBound, calendar: calendar)
        guard weekly else { return dates.map { $0 ... $0 } }
        var groups: [ClosedRange<DayKey>] = []
        var start = span.lowerBound
        for day in dates.dropFirst() {
            if calendar.component(.weekday, from: day.start(in: calendar)) == calendar.firstWeekday {
                groups.append(start ... day.advanced(by: -1, calendar: calendar))
                start = day
            }
        }
        groups.append(start ... span.upperBound)
        return groups
    }
}
