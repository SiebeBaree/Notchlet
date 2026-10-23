import SwiftUI

/// One provider's full breakdown, or a summary gauge per provider with the
/// hovered one unfolded below. A provider that is on but has no window to
/// draw keeps its place and says why: still fetching, signed out, rate
/// limited, a plan without limits.
struct UsagePane: View {
    let store: UsageStore
    @Binding var focusedProviderID: String?
    let showHistory: (String) -> Void

    /// The provider shown when exactly one is on. `NotchView` puts its name
    /// beside the notch cutout, so the pane itself leaves the name out.
    static func soloEntry(in store: UsageStore) -> UsageStore.Entry? {
        let shown = shownEntries(in: store)
        return shown.count == 1 ? shown.first : nil
    }

    static func shownEntries(in store: UsageStore) -> [UsageStore.Entry] {
        store.entries.filter { store.isEnabled($0.id) }
    }

    var body: some View {
        content
        footer
    }

    @ViewBuilder
    private var content: some View {
        let shown = Self.shownEntries(in: store)
        if shown.isEmpty {
            Text(UsageCopy.noProviderText(names: store.entries.map(\.provider.name)))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        } else if shown.count == 1, let entry = shown.first {
            detail(for: entry, ringDiameter: 62)
                .contentShape(.rect)
                .onTapGesture { showHistory(entry.id) }
        } else {
            HStack(alignment: .top, spacing: 0) {
                ForEach(shown) { entry in
                    ProviderSummary(
                        entry: entry,
                        isFocused: focusedProviderID == entry.id,
                        isDimmed: focusedProviderID != nil && focusedProviderID != entry.id
                    )
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                    .onTapGesture { showHistory(entry.id) }
                    .onHover { hovering in
                        guard hovering else { return }
                        withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                            focusedProviderID = entry.id
                        }
                    }
                }
            }
            if let focused = shown.first(where: { $0.id == focusedProviderID }) {
                NotchRule()
                detail(for: focused, ringDiameter: 48)
            }
        }
    }

    /// The windows, or the full reason there are none.
    @ViewBuilder
    private func detail(for entry: UsageStore.Entry, ringDiameter: CGFloat) -> some View {
        if let windows = entry.snapshot?.windows, !windows.isEmpty {
            WindowRow(windows: windows, ringDiameter: ringDiameter)
        } else {
            HStack(spacing: 14) {
                PendingRing(state: entry.state, diameter: ringDiameter)
                Text(entry.pendingStatus.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(entry.hasProblem ? NotchPalette.amber : .white.opacity(0.85))
                Spacer(minLength: 0)
            }
        }
    }

    /// Only a rate limit earns a line under numbers it has frozen; the
    /// refresh button carries everything else. A provider without numbers
    /// says so in its own column.
    @ViewBuilder
    private var footer: some View {
        let limited = Self.shownEntries(in: store)
            .filter { $0.snapshot != nil && $0.state == .rateLimited }
            .compactMap { entry in entry.schedule.retryAt.map { (name: entry.provider.name, retryAt: $0) } }
            .min { $0.retryAt < $1.retryAt }
        if let limited {
            Text(UsageCopy.rateLimitText(providerName: limited.name, retryAt: limited.retryAt))
                .font(.system(size: 10))
                .foregroundStyle(NotchPalette.amber)
        }
    }
}

/// Fetches every shown provider, and turns into a spinner while any of
/// them fetches, whoever started it. Amber means a provider shows numbers
/// it could not refresh, so stale numbers never pass as live. `showsAge`
/// adds how old the oldest numbers are, for the ear beside the cutout.
struct UsageRefreshButton: View {
    let store: UsageStore
    var showsAge = false

    @State private var isSpinning = false
    @State private var isHovering = false

    private var shown: [UsageStore.Entry] {
        UsagePane.shownEntries(in: store)
    }

    private var isFetching: Bool {
        shown.contains { store.fetchingIDs.contains($0.id) }
    }

    var body: some View {
        let withNumbers = shown.filter { $0.snapshot != nil }
        let isStale = withNumbers.contains { $0.state != .ok }
        // `NotchIconButton`'s opacities, so it reads as one of the icons.
        let tint = isStale ? NotchPalette.amber : .white
        Button(action: refresh) {
            HStack(spacing: 4) {
                Group {
                    if isSpinning {
                        ProgressView()
                            .controlSize(.mini)
                            .colorScheme(.dark)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(tint.opacity(isHovering ? 0.85 : isStale ? 0.7 : 0.35))
                    }
                }
                .frame(width: 18, height: 18)
                if showsAge, let oldest = withNumbers.compactMap(\.snapshot?.fetchedAt).min() {
                    FetchAge(fetchedAt: oldest)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(isHovering ? 0.85 : 0.4))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        // Held a moment past the fetch, so a quick one reads as a spin
        // rather than a flicker.
        .task(id: isFetching) {
            if isFetching {
                isSpinning = true
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled {
                isSpinning = false
            }
        }
    }

    private func refresh() {
        isSpinning = true
        store.refreshShownNow()
        // A click with nothing due still shows it was heard.
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            if !isFetching {
                isSpinning = false
            }
        }
    }
}

/// "4m ago", kept current while the notch is open; the view only exists
/// then, so the timeline costs nothing while closed.
struct FetchAge: View {
    let fetchedAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(UsageCopy.fetchAgeText(fetchedAt: fetchedAt, now: context.date))
        }
    }
}

private extension UsageStore.Entry {
    var pendingStatus: (title: String, detail: String) {
        UsageCopy.pendingStatus(state: state, signInHint: provider.signInHint, retryAt: schedule.retryAt)
    }

    /// Fetching and a plan without limits are not problems.
    var hasProblem: Bool {
        state != nil && state != .ok
    }
}

/// The primary window's gauge, label and pace, or the pending ring with
/// the short reason.
private struct ProviderSummary: View {
    let entry: UsageStore.Entry
    let isFocused: Bool
    let isDimmed: Bool

    var body: some View {
        VStack(spacing: 6) {
            BrandRow(provider: entry.provider)
            if let window = entry.snapshot?.primaryWindow {
                let projection = BurnProjection.project(window)
                UsageRing(
                    remainingFraction: window.remainingFraction,
                    expectedRemainingFraction: window.expectedRemainingFraction(),
                    color: NotchPalette.pace(projection?.verdict),
                    diameter: 62
                )
                VStack(spacing: 1) {
                    Text(window.label)
                        .foregroundStyle(.white.opacity(0.55))
                    if let pace = UsageCopy.paceText(projection: projection, resetsAt: window.resetsAt) {
                        Text(pace)
                            .foregroundStyle(NotchPalette.pace(projection?.verdict))
                    }
                }
                .font(.system(size: 10.5))
            } else {
                PendingRing(state: entry.state, diameter: 62)
                Text(entry.pendingStatus.title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(entry.hasProblem ? NotchPalette.amber : .white.opacity(0.55))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            isFocused ? .white.opacity(0.08) : .clear,
            in: .rect(cornerRadius: 12)
        )
        .opacity(isDimmed ? 0.55 : 1)
    }
}

/// The gauge's track with a glyph where the number would be, so a column
/// without data lines up with the ones that have it.
private struct PendingRing: View {
    let state: UsageStore.ProviderState?
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.17), lineWidth: diameter / 12)
            Image(systemName: glyph)
                .font(.system(size: diameter * 0.26, weight: .semibold))
                .foregroundStyle(state == nil || state == .ok ? .white.opacity(0.55) : NotchPalette.amber)
        }
        .frame(width: diameter, height: diameter)
    }

    private var glyph: String {
        switch state {
        case nil: "ellipsis"
        case .ok: "infinity"
        case .rateLimited: "clock"
        case .notAvailable, .error: "exclamationmark"
        }
    }
}

private struct WindowRow: View {
    let windows: [UsageWindow]
    let ringDiameter: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(windows) { window in
                WindowColumn(window: window, ringDiameter: ringDiameter)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct WindowColumn: View {
    let window: UsageWindow
    let ringDiameter: CGFloat

    var body: some View {
        let projection = BurnProjection.project(window)
        VStack(spacing: 6) {
            Text(window.label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
            UsageRing(
                remainingFraction: window.remainingFraction,
                expectedRemainingFraction: window.expectedRemainingFraction(),
                color: NotchPalette.pace(projection?.verdict),
                diameter: ringDiameter
            )
            VStack(spacing: 1) {
                if let reset = UsageCopy.resetText(for: window.resetsAt) {
                    Text(reset)
                        .foregroundStyle(.white.opacity(0.55))
                }
                if let pace = UsageCopy.paceText(projection: projection, resetsAt: window.resetsAt) {
                    Text(pace)
                        .foregroundStyle(NotchPalette.pace(projection?.verdict))
                }
            }
            .font(.system(size: 10.5))
        }
    }
}
