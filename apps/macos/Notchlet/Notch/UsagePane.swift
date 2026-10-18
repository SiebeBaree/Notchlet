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

    /// Nothing while the data is fresh, so stale numbers never pass as live.
    /// A provider without numbers says so in its own column.
    @ViewBuilder
    private var footer: some View {
        let shown = Self.shownEntries(in: store).filter { $0.snapshot != nil }
        let limited = shown
            .filter { $0.state == .rateLimited }
            .compactMap { entry in entry.schedule.retryAt.map { (name: entry.provider.name, retryAt: $0) } }
            .min { $0.retryAt < $1.retryAt }
        if let limited {
            Text(UsageCopy.rateLimitText(providerName: limited.name, retryAt: limited.retryAt))
                .font(.system(size: 10))
                .foregroundStyle(NotchPalette.amber)
        } else if let oldest = shown.compactMap(\.snapshot?.fetchedAt).min(),
                  let text = UsageCopy.freshnessText(fetchedAt: oldest)
        {
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
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
