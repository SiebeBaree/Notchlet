import SwiftUI

/// Root view of the panel. The collapsed notch shape shows nothing; hovering
/// expands it into the usage card. With one active provider the card shows
/// its full breakdown directly. With two or three it shows one summary gauge
/// per provider (its tightest window), and hovering a gauge unfolds that
/// provider's breakdown below.
///
/// Known limitation of the skeleton: the hosting window is always
/// `NotchGeometry.panelSize`, so the transparent area around the collapsed
/// shape still swallows clicks. Fixing hit-testing (click-through for
/// transparent pixels) is on the roadmap.
struct NotchView: View {
    /// What the expanded panel shows: usage, or in-notch settings behind the
    /// small gear in the corner.
    private enum Pane {
        case usage
        case settings
    }

    let store: UsageStore
    let updater: UpdateController
    let notchSize: CGSize

    @State private var isExpanded = false
    @State private var focusedProviderID: String?
    @State private var pane: Pane = .usage
    @State private var openedAt: Date?
    @State private var openDebounce: Task<Void, Never>?

    private var activeEntries: [UsageStore.Entry] {
        store.entries.filter { $0.snapshot != nil }
    }

    private var expandedWidth: CGFloat {
        max(notchSize.width + 220, 430)
    }

    var body: some View {
        VStack(spacing: 0) {
            shape
                .onHover { hovering in
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                        isExpanded = hovering
                        if !hovering {
                            focusedProviderID = nil
                            pane = .usage
                        }
                    }
                    trackOpenClose(hovering: hovering)
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var shape: some View {
        ZStack(alignment: .top) {
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: (isExpanded ? expandedWidth : notchSize.width) + 2 * NotchGeometry.notchTopCornerRadius)
        .frame(height: isExpanded ? nil : notchSize.height, alignment: .top)
        .background(
            .black,
            in: NotchShape(
                topRadius: NotchGeometry.notchTopCornerRadius,
                bottomRadius: isExpanded ? 20 : 10
            )
        )
    }

    /// Debounced open plus close-with-duration analytics. The 250ms delay
    /// keeps accidental hover grazes out of the numbers.
    private func trackOpenClose(hovering: Bool) {
        if hovering {
            openDebounce = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                openedAt = .now
                Analytics.capture(.notchOpened)
            }
        } else {
            openDebounce?.cancel()
            if let openedAt {
                Analytics.capture(.notchClosed(openSeconds: Date.now.timeIntervalSince(openedAt)))
                self.openedAt = nil
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Leave room for the physical notch cutout.
            Spacer().frame(height: notchSize.height)

            if pane == .settings {
                NotchSettingsView(updater: updater)
            } else {
                usageContent
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) { cornerIcons }
    }

    /// The gear lives in the strip beside the notch cutout, quiet until
    /// hovered. The update icon only exists when an update is waiting.
    private var cornerIcons: some View {
        HStack(spacing: 6) {
            if updater.availableUpdateVersion != nil {
                NotchIconButton(systemName: "arrow.down.circle.fill") {
                    updater.installAvailableUpdate()
                }
            }
            NotchIconButton(systemName: "gearshape.fill", isActive: pane == .settings) {
                withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                    pane = pane == .settings ? .usage : .settings
                }
                if pane == .settings {
                    Analytics.capture(.settingsOpened)
                }
            }
        }
        .frame(height: notchSize.height)
        .padding(.trailing, 14)
    }

    @ViewBuilder
    private var usageContent: some View {
        let active = activeEntries
        if active.isEmpty {
            Text("No usage data yet")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        } else if active.count == 1, let entry = active.first, let snapshot = entry.snapshot {
            BrandRow(provider: entry.provider)
            WindowRow(windows: snapshot.windows, ringDiameter: 62)
        } else {
            HStack(alignment: .top, spacing: 0) {
                ForEach(active) { entry in
                    ProviderSummary(
                        entry: entry,
                        isFocused: focusedProviderID == entry.id,
                        isDimmed: focusedProviderID != nil && focusedProviderID != entry.id
                    )
                    .frame(maxWidth: .infinity)
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
                Rectangle()
                    .fill(.white.opacity(0.15))
                    .frame(height: 1)
                WindowRow(windows: snapshot.windows, ringDiameter: 48)
            }
        }
    }
}

/// Small corner icon, grayish until hovered or active.
private struct NotchIconButton: View {
    let systemName: String
    var isActive = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(isActive || isHovering ? 0.85 : 0.35))
                .frame(width: 18, height: 18)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private func paceColor(_ verdict: BurnProjection.Verdict?) -> Color {
    switch verdict {
    case .early: Color(red: 1.0, green: 0.42, blue: 0.34)
    case .onPace: Color(red: 1.0, green: 0.84, blue: 0.04)
    case .plenty: Color(red: 0.2, green: 0.84, blue: 0.29)
    case nil: .white
    }
}

/// Provider logo and name.
private struct BrandRow: View {
    let provider: any UsageProvider

    var body: some View {
        HStack(spacing: 7) {
            Image(provider.logoAssetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .foregroundStyle(.white)
            Text(provider.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// One provider's at-a-glance gauge: brand on top, then the tightest window
/// with its label and pace, so a glance still tells you which limit is
/// squeezed.
private struct ProviderSummary: View {
    let entry: UsageStore.Entry
    let isFocused: Bool
    let isDimmed: Bool

    var body: some View {
        VStack(spacing: 6) {
            BrandRow(provider: entry.provider)
            if let window = entry.snapshot?.tightestWindow {
                let projection = BurnProjection.project(window)
                UsageRing(
                    remainingFraction: window.remainingFraction,
                    color: paceColor(projection?.verdict),
                    diameter: 62
                )
                VStack(spacing: 1) {
                    Text(window.label)
                        .foregroundStyle(.white.opacity(0.55))
                    if let pace = UsageCopy.paceText(projection: projection, resetsAt: window.resetsAt) {
                        Text(pace)
                            .foregroundStyle(paceColor(projection?.verdict))
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
                color: paceColor(projection?.verdict),
                diameter: ringDiameter
            )
            VStack(spacing: 1) {
                if let reset = UsageCopy.resetText(for: window.resetsAt) {
                    Text(reset)
                        .foregroundStyle(.white.opacity(0.55))
                }
                if let pace = UsageCopy.paceText(projection: projection, resetsAt: window.resetsAt) {
                    Text(pace)
                        .foregroundStyle(paceColor(projection?.verdict))
                }
            }
            .font(.system(size: 10.5))
        }
    }
}

/// Circular gauge of what's left, with the percentage and a tiny "left"
/// inside.
private struct UsageRing: View {
    let remainingFraction: Double
    let color: Color
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.17), lineWidth: diameter / 12)
            Circle()
                .trim(from: 0, to: remainingFraction)
                .stroke(color, style: StrokeStyle(lineWidth: diameter / 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text("\(Int((remainingFraction * 100).rounded()))%")
                    .font(.system(size: diameter * 0.23, weight: .semibold))
                    .foregroundStyle(.white)
                Text("left")
                    .font(.system(size: diameter * 0.11))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(width: diameter, height: diameter)
    }
}
