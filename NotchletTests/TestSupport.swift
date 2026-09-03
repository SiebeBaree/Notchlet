import Foundation
@testable import Notchlet

/// Fixture helpers shared by the history tests.
enum TestSupport {
    /// A `DayKey` from "yyyy-MM-dd"; a typo in a fixture fails loudly.
    static func day(_ string: String) -> DayKey {
        guard let day = DayKey(string) else { fatalError("Not a day: \(string)") }
        return day
    }

    static func date(_ iso: String) -> Date {
        guard let date = ISO8601DateFormatter().date(from: iso) else { fatalError("Not a date: \(iso)") }
        return date
    }
}
