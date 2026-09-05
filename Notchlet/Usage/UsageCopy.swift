import Foundation

/// The usage card's strings.
enum UsageCopy {
    /// "Resets in 51m" within a day, "Resets Fri 11:00" within a week,
    /// "Resets Sep 28" beyond that: a bare weekday a month out reads as this
    /// coming Monday.
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

    /// "Plenty", "On pace" or "Empty 3h 10m early"; nil without a projection.
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

    /// "5h limit past 80%", or "Weekly limit used up" at 100.
    static func alertHeadline(windowLabel: String, percent: Int) -> String {
        percent >= 100 ? "\(windowLabel) limit used up" : "\(windowLabel) limit past \(percent)%"
    }

    /// "Updated 5m ago"; nil under 2 minutes.
    static func freshnessText(fetchedAt: Date?, now: Date = .now) -> String? {
        guard let fetchedAt else { return nil }
        let age = now.timeIntervalSince(fetchedAt)
        guard age > 120 else { return nil }
        return "Updated \(shortDuration(age)) ago"
    }

    /// "Codex rate limited, retrying in 4m".
    static func rateLimitText(providerName: String, retryAt: Date, now: Date = .now) -> String {
        let wait = retryAt.timeIntervalSince(now)
        guard wait > 0 else {
            return "\(providerName) rate limited, retrying soon"
        }
        return "\(providerName) rate limited, retrying in \(shortDuration(wait))"
    }

    /// The settings status line: what it signed in with, or why it could
    /// not and what to do about it.
    static func providerStatusText(
        state: UsageStore.ProviderState?,
        option: AuthOption?,
        signInHint: String,
        retryAt: Date?,
        now: Date = .now
    ) -> String {
        switch state {
        case nil:
            return "Fetching usage"
        case .ok:
            guard let option else { return "Signed in" }
            return option.secretName.map { "Using the pasted \($0)" } ?? "Using \(option.label)"
        case .notAvailable, .rateLimited, .error:
            return pendingStatus(state: state, signInHint: signInHint, retryAt: retryAt, now: now).detail
        }
    }

    /// What the usage card says about a provider that has no windows to
    /// draw: a short title for its column and the full line for the
    /// drill-in and the single-provider card.
    static func pendingStatus(
        state: UsageStore.ProviderState?,
        signInHint: String,
        retryAt: Date?,
        now: Date = .now
    ) -> (title: String, detail: String) {
        switch state {
        case nil:
            return ("Fetching", "Fetching usage")
        case .ok:
            return ("No limits", "This plan reports no rate limits")
        case let .notAvailable(problem):
            let title = switch problem {
            case .rejected: "Login rejected"
            case .expired: "Login expired"
            case .signedOut: "Not signed in"
            }
            return (title, "\(title). \(signInHint).")
        case .rateLimited:
            return ("Rate limited", "Rate limited, retrying \(retryText(retryAt, now: now))")
        case .error:
            return ("Request failed", "Request failed, retrying \(retryText(retryAt, now: now))")
        }
    }

    /// "Claude Code, Codex, Cursor or OpenCode" for the card with no
    /// provider on.
    static func noProviderText(names: [String]) -> String {
        let list = names.count > 1
            ? names.dropLast().joined(separator: ", ") + " or " + names[names.count - 1]
            : names.first ?? "an agent CLI"
        return "No coding agent found. Install \(list), or turn one on under Providers in settings."
    }

    /// "in 4m", or "soon" once the retry time has passed.
    private static func retryText(_ retryAt: Date?, now: Date) -> String {
        guard let retryAt, retryAt > now else { return "soon" }
        return "in \(shortDuration(retryAt.timeIntervalSince(now)))"
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
