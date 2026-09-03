import Foundation

/// Number and date formatting for the history pane. Pure, and pinned to
/// en_US so a token count reads the same on every Mac: the pane is too
/// small for locale-sized numbers and the dollar sign is the unit.
nonisolated enum HistoryCopy {
    private static let locale = Locale(identifier: "en_US")

    /// "412", "9.8K", "412K", "41.3M", "120M", "1.2B".
    static func tokens(_ count: Int) -> String {
        let value = Double(count)
        switch value {
        case ..<1000:
            return String(count)
        case ..<10000:
            return scaled(value / 1000, "K")
        case ..<1_000_000:
            return "\(Int((value / 1000).rounded()))K"
        case ..<100_000_000:
            return scaled(value / 1_000_000, "M")
        case ..<1_000_000_000:
            return "\(Int((value / 1_000_000).rounded()))M"
        default:
            return scaled(value / 1_000_000_000, "B")
        }
    }

    /// One decimal, dropped when it is zero: "9.8K", "10K".
    private static func scaled(_ value: Double, _ unit: String) -> String {
        let rounded = (value * 10).rounded() / 10
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return text + unit
    }

    /// "$0.04", "$4.21", "$118.40", "$1,204". Cents matter below a
    /// thousand dollars and are noise above it.
    static func cost(_ dollars: Double) -> String {
        if dollars < 0.005, dollars > 0 {
            return "<$0.01"
        }
        let digits = dollars < 1000 ? 2 : 0
        return "$" + dollars.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }

    /// "Wed, Aug 12".
    static func dayTitle(_ day: DayKey, calendar: Calendar) -> String {
        day.start(in: calendar).formatted(style(calendar).weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "Aug 12" for the axis and the footer.
    static func shortDay(_ day: DayKey, calendar: Calendar) -> String {
        day.start(in: calendar).formatted(style(calendar).day().month(.abbreviated))
    }

    /// "Aug 12, 2026" where the year matters, as on a shared image.
    static func fullDay(_ day: DayKey, calendar: Calendar) -> String {
        day.start(in: calendar).formatted(style(calendar).day().month(.abbreviated).year())
    }

    /// "Aug 2026".
    static func monthYear(_ day: DayKey, calendar: Calendar) -> String {
        day.start(in: calendar).formatted(style(calendar).month(.abbreviated).year())
    }

    /// No fields until one is added, in the calendar's own time zone so
    /// midnight stays on its day.
    private static func style(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(
            date: .omitted,
            time: .omitted,
            locale: locale,
            calendar: calendar,
            timeZone: calendar.timeZone
        )
    }

    /// The pane's footer: the pricing caveat, then what could not be
    /// priced, then how far back the archive goes when that is less than
    /// the graph shows.
    static func footer(unpricedModels: [String], coverageStart: DayKey?, graphStart: DayKey,
                       calendar: Calendar) -> String
    {
        (["Cost at API list prices"] + caveats(
            unpricedModels: unpricedModels, coverageStart: coverageStart, graphStart: graphStart, calendar: calendar
        )).joined(separator: " · ")
    }

    /// What could not be priced, then how far back the archive goes when
    /// that is less than the graph shows. Empty when there is nothing to
    /// caveat.
    static func caveats(unpricedModels: [String], coverageStart: DayKey?, graphStart: DayKey,
                        calendar: Calendar) -> [String]
    {
        var parts: [String] = []
        switch unpricedModels.count {
        case 0:
            break
        case 1:
            parts.append("\(unpricedModels[0]) not priced")
        case 2:
            parts.append("\(unpricedModels[0]) and \(unpricedModels[1]) not priced")
        default:
            parts.append("\(unpricedModels[0]) and \(unpricedModels.count - 1) more not priced")
        }
        if let coverageStart, coverageStart > graphStart {
            parts.append("History since \(shortDay(coverageStart, calendar: calendar))")
        }
        return parts
    }
}
