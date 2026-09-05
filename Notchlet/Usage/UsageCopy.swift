import Foundation

/// User-facing strings for reset times and pace verdicts. Pure so the date
/// edge cases stay testable.
enum UsageCopy {
    /// "Resets in 51m" within a day, "Resets Fri 11:00" within a week, and
    /// "Resets Sep 28" beyond that — a bare weekday a month out reads as
    /// "this coming Monday".
    static func resetText(for resetsAt: Date?, now: Date = .now) -> String? {
        guard let resetsAt else { return nil }
        let interval = resetsAt.timeIntervalSince(now)
        if interval <= 0 {
            return "Resets soon"
        }
        if interval < 24 * 3600 {
            return "Resets in \(shortDuration(interval))"
        }
        if interval < 7 * 24 * 3600 {
            let weekday = resetsAt.formatted(.dateTime.weekday(.abbreviated))
            let time = resetsAt.formatted(date: .omitted, time: .shortened)
            return "Resets \(weekday) \(time)"
        }
        return "Resets \(resetsAt.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// The pace verdict, nil when there is none to show (missing or stale
    /// reset data). The early case says how far ahead of the reset the window
    /// runs out.
    static func paceText(projection: BurnProjection?, resetsAt: Date?, now: Date = .now) -> String? {
        guard let projection else { return nil }
        switch projection.verdict {
        case .plenty:
            return "Plenty"
        case .onPace:
            return "On pace"
        case .early:
            guard let resetsAt, let depletion = projection.depletionDate else { return "Running out" }
            return "Empty \(shortDuration(resetsAt.timeIntervalSince(depletion))) early"
        }
    }

    /// Headline of a usage alert: the window's own label, then how far it
    /// is. "5h limit past 80%", or "Weekly limit used up" at 100.
    static func alertHeadline(windowLabel: String, percent: Int) -> String {
        percent >= 100 ? "\(windowLabel) limit used up" : "\(windowLabel) limit past \(percent)%"
    }

    /// Footer line for data old enough to mention; under 2 minutes counts as
    /// fresh and shows nothing.
    static func freshnessText(fetchedAt: Date?, now: Date = .now) -> String? {
        guard let fetchedAt else { return nil }
        let age = now.timeIntervalSince(fetchedAt)
        guard age > 120 else { return nil }
        return "Updated \(shortDuration(age)) ago"
    }

    /// Footer line while a provider is rate limited: names the provider and
    /// when the next attempt happens.
    static func rateLimitText(providerName: String, retryAt: Date, now: Date = .now) -> String {
        let wait = retryAt.timeIntervalSince(now)
        guard wait > 0 else {
            return "\(providerName) rate limited, retrying soon"
        }
        return "\(providerName) rate limited, retrying in \(shortDuration(wait))"
    }

    /// The status line on a provider's settings page: what it signed in
    /// with, or why it could not, followed by what to do about it.
    static func providerStatusText(
        state: UsageStore.ProviderState?,
        option: AuthOption?,
        signInHint: String,
        retryAt: Date?,
        now: Date = .now
    ) -> String {
        switch state {
        case nil:
            return "Waiting for the first refresh"
        case .ok:
            guard let option else { return "Signed in" }
            return option.secretName.map { "Using the pasted \($0)" } ?? "Using \(option.label)"
        case let .notAvailable(problem):
            let reason = switch problem {
            case .rejected: "Login rejected."
            case .expired: "Login expired."
            case .signedOut: "Not signed in."
            }
            return "\(reason) \(signInHint)."
        case .rateLimited:
            guard let retryAt, retryAt > now else { return "Rate limited, retrying soon" }
            return "Rate limited, retrying in \(shortDuration(retryAt.timeIntervalSince(now)))"
        case .error:
            guard let retryAt, retryAt > now else { return "Request failed, retrying soon" }
            return "Request failed, retrying in \(shortDuration(retryAt.timeIntervalSince(now)))"
        }
    }

    /// "51m", "3h 10m" or "4d 16h", never "0m" for a positive interval.
    /// Two units at most; day-scale durations drop the minutes.
    static func shortDuration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded()))
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        if hours < 24 {
            let remainder = minutes % 60
            return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
        }
        let remainder = hours % 24
        return remainder == 0 ? "\(hours / 24)d" : "\(hours / 24)d \(remainder)h"
    }
}
