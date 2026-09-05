import SwiftUI

/// The usage card: one provider's full breakdown, or a summary gauge per
/// provider with the hovered one unfolded below, then the freshness footer.
struct UsagePane: View {
    let store: UsageStore
    @Binding var focusedProviderID: String?
    let showHistory: (String) -> Void

    /// Providers with something to draw. A snapshot without windows (an
    /// unlimited plan, say) would be a brand row over nothing, so it counts
    /// as no data.
    private var activeEntries: [UsageStore.Entry] {
        store.entries.filter { store.isEnabled($0.id) && $0.snapshot?.windows.isEmpty == false }
    }

    var body: some View {
        content
        footer
    }

    @ViewBuilder
    private var content: some View {
        let active = activeEntries
        if active.isEmpty {
            Text("No usage data yet")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        } else if active.count == 1, let entry = active.first, let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 12) {
                BrandRow(provider: entry.provider)
                WindowRow(windows: snapshot.windows, ringDiameter: 62)
            }
            .contentShape(.rect)
            .onTapGesture { showHistory(entry.id) }
        } else {
            HStack(alignment: .top, spacing: 0) {
                ForEach(active) { entry in
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
            if let focused = active.first(where: { $0.id == focusedProviderID }),
               let snapshot = focused.snapshot
            {
                NotchRule()
                WindowRow(windows: snapshot.windows, ringDiameter: 48)
            }
        }
    }

    /// Fresh data shows nothing here. Data older than a couple of minutes
    /// gets a quiet age line, and a rate-limited provider gets an amber line
    /// naming it and its next retry, so stale numbers never pass as live.
    @ViewBuilder
    private var footer: some View {
        let limited = store.entries
            .filter { store.isEnabled($0.id) && $0.state == .rateLimited }
            .compactMap { entry in entry.schedule.retryAt.map { (name: entry.provider.name, retryAt: $0) } }
            .min { $0.retryAt < $1.retryAt }
        if let limited {
            Text(UsageCopy.rateLimitText(providerName: limited.name, retryAt: limited.retryAt))
                .font(.system(size: 10))
                .foregroundStyle(NotchPalette.amber)
        } else if let oldest = activeEntries.compactMap(\.snapshot?.fetchedAt).min(),
                  let text = UsageCopy.freshnessText(fetchedAt: oldest)
        {
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

/// One provider's at-a-glance gauge: brand on top, then the primary window
/// with its label and pace.
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

/// A provider's full breakdown: one column per window.
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

/// Name above the gauge, reset time and pace verdict below it.
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
