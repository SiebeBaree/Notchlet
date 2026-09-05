import SwiftUI

/// Root view of the panel. The collapsed notch shape shows nothing; hovering
/// expands it into the usage card. With one active provider the card shows
/// its full breakdown directly. With two or three it shows one summary gauge
/// per provider (its primary window), and hovering a gauge unfolds that
/// provider's breakdown below. Clicking a gauge, or the history icon in the
/// corner, swaps the card for the history pane at the same width.
///
/// Only the notch shape is drawn: the panel is non-opaque and nothing else
/// paints a background, so clicks in the transparent area go to the window
/// below. The window controller sizes the window to what is drawn.
struct NotchView: View {
    /// What the expanded panel shows: usage, past usage behind the history
    /// icon, leaked secrets behind the key, a usage alert that opened the
    /// notch on its own, or in-notch settings behind the gear.
    private enum Pane {
        case usage
        case history
        case secrets
        case alerts
        case settings
    }

    let store: UsageStore
    let history: UsageHistory
    let updater: UpdateController
    let scanner: SecretScanner
    let alerts: UsageAlerts
    let waits: AgentWaits
    let notchSize: CGSize
    /// Tells the window controller to grow the window before the card
    /// expands or the wait line appears, and to shrink it once the collapse
    /// animation has ended.
    let resizePanel: (_ expanded: Bool, _ waiting: Bool) -> Void
    /// Opens the share editor for a scope.
    let share: (UsageHistory.Scope) -> Void

    @State private var isExpanded = false
    @State private var focusedProviderID: String?
    @State private var pane: Pane = .usage
    /// The history pane's scope, remembered across opens.
    @AppStorage("historyScope") private var historyScope = "all"
    @State private var openedAt: Date?
    @State private var openDebounce: Task<Void, Never>?
    @State private var isHovering = false
    /// Folds an alert the user never hovered back into the notch.
    @State private var autoCollapse: Task<Void, Never>?
    /// The notch is grown and outlined for a waiting agent. Mirrors
    /// `waits.isWaiting` while collapsed so the change can animate and the
    /// window can shrink after it.
    @State private var isOutlined = false

    /// Providers with something to draw. A snapshot without windows (an
    /// unlimited plan, say) would be a brand row over nothing, so it counts
    /// as no data.
    private var activeEntries: [UsageStore.Entry] {
        store.entries.filter { store.isEnabled($0.id) && $0.snapshot?.windows.isEmpty == false }
    }

    private var expandedWidth: CGFloat {
        max(notchSize.width + 220, 430)
    }

    var body: some View {
        VStack(spacing: 0) {
            shape
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        autoCollapse?.cancel()
                        // Opening the notch is looking; the wait line is done.
                        waits.clearAll(by: "hover")
                        // An alert nobody acknowledged is the first thing
                        // a hover shows, until it is.
                        if !isExpanded, alerts.current != nil {
                            pane = .alerts
                        }
                    }
                    setExpanded(hovering)
                    store.setPanelOpen(hovering)
                    trackOpenClose(hovering: hovering)
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .onChange(of: waits.isWaiting, initial: true) { _, waiting in
            if !isExpanded {
                setOutlined(waiting)
            }
        }
        .onChange(of: scanner.alertGeneration) { _, _ in showAlert(.secrets) }
        .onChange(of: alerts.alertGeneration) { _, _ in showAlert(.alerts) }
        .onChange(of: alerts.current == nil) { _, none in
            // Got it on the last notice hands the panel back to usage.
            if none, pane == .alerts {
                show(.usage)
            }
        }
    }

    /// A new leaked key or a usage alert opens the notch on its own for
    /// twelve seconds, or for as long as the mouse is in it. Not through
    /// `setPanelOpen`: an alert is not the user looking at usage, so it
    /// never speeds up the polling. A panel already open on another pane
    /// keeps it: the key icon lights up in the corner, and a usage alert
    /// comes first on the next hover.
    private func showAlert(_ target: Pane) {
        guard !isExpanded else { return }
        pane = target
        setExpanded(true)
        autoCollapse = Task {
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, !isHovering else { return }
            setExpanded(false)
        }
    }

    private var shape: some View {
        let growth = isOutlined ? NotchGeometry.waitInset : 0
        let bottomRadius: CGFloat = isExpanded ? 20 : 10 + growth
        return ZStack(alignment: .top) {
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: (isExpanded ? expandedWidth : notchSize.width) + 2 * NotchGeometry
            .notchTopCornerRadius + 2 * growth)
        .frame(height: isExpanded ? nil : notchSize.height + growth, alignment: .top)
        .background(
            .black,
            in: NotchShape(
                topRadius: NotchGeometry.notchTopCornerRadius,
                bottomRadius: bottomRadius
            )
        )
        .overlay {
            if isOutlined {
                WaitOutline(
                    color: waits.needsInput ? NSColor(SecretsPane.amber) : .systemBlue,
                    topRadius: NotchGeometry.notchTopCornerRadius,
                    bottomRadius: bottomRadius,
                    inset: NotchGeometry.waitLineInset,
                    lineWidth: NotchGeometry.waitLineWidth
                )
                .transition(.opacity)
            }
        }
    }

    /// Grows the notch for the wait line and shrinks it back, with the
    /// window resized around the animation the way `setExpanded` does.
    private func setOutlined(_ outlined: Bool) {
        guard outlined != isOutlined else { return }
        if outlined {
            resizePanel(false, true)
        }
        withAnimation(.spring(duration: 0.35, bounce: 0.15), completionCriteria: .removed) {
            isOutlined = outlined
        } completion: {
            if !isOutlined, !isExpanded {
                resizePanel(false, false)
            }
        }
    }

    /// Animates between the notch and the card. The window grows before the
    /// card appears and shrinks only once the collapse has fully settled;
    /// a hover that returns mid-collapse keeps the window as it is.
    private func setExpanded(_ expanded: Bool) {
        if expanded {
            resizePanel(true, false)
        }
        withAnimation(.spring(duration: 0.35, bounce: 0.15), completionCriteria: .removed) {
            isExpanded = expanded
            // A wait that arrived while the card was open shows on the
            // way back down.
            isOutlined = !expanded && waits.isWaiting
            if !expanded {
                focusedProviderID = nil
                pane = .usage
            }
        } completion: {
            if !isExpanded {
                resizePanel(false, isOutlined)
            }
        }
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

            switch pane {
            case .settings:
                NotchSettingsView(store: store, updater: updater, scanner: scanner, alerts: alerts, waits: waits)
            case .secrets:
                SecretsPane(scanner: scanner)
            case .alerts:
                AlertsPane(alerts: alerts, store: store)
            case .history:
                HistoryPane(history: history, scope: Binding(
                    get: { resolvedScope },
                    set: { historyScope = $0.storedValue }
                ))
            case .usage:
                usageContent
                freshnessFooter
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) { cornerIcons }
    }

    /// The share, history and gear icons live in the strip beside the notch
    /// cutout, quiet until hovered. The key's slot holds a spinner while a
    /// scan runs and the key only while a leaked secret waits; the update
    /// icon only exists while an update does. Share is dimmed until some
    /// history exists.
    private var cornerIcons: some View {
        HStack(spacing: 6) {
            if scanner.isScanning {
                Button {
                    toggle(.secrets)
                } label: {
                    ProgressView()
                        .controlSize(.mini)
                        .colorScheme(.dark)
                        .frame(width: 18, height: 18)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(SecretsPane.statusText(.scanning) ?? "")
            } else if !scanner.pending.isEmpty {
                NotchIconButton(systemName: "key.fill", isActive: pane == .secrets, tint: SecretsPane.amber) {
                    toggle(.secrets)
                }
            }
            if updater.availableUpdateVersion != nil {
                NotchIconButton(systemName: "arrow.down.circle.fill") {
                    updater.installAvailableUpdate()
                }
            }
            NotchIconButton(systemName: "square.and.arrow.up") {
                share(pane == .history ? resolvedScope : .all)
            }
            .disabled(history.providersWithHistory.isEmpty)
            .opacity(history.providersWithHistory.isEmpty ? 0.4 : 1)
            NotchIconButton(systemName: "chart.bar.fill", isActive: pane == .history) {
                toggle(.history)
            }
            NotchIconButton(systemName: "gearshape.fill", isActive: pane == .settings) {
                toggle(.settings)
            }
        }
        .frame(height: notchSize.height)
        .padding(.trailing, 14)
    }

    /// The remembered scope, or all when its provider no longer has
    /// history (switched off, say): a scope with no data and no chips to
    /// leave it would be a dead end.
    private var resolvedScope: UsageHistory.Scope {
        let scope = UsageHistory.Scope(storedValue: historyScope)
        if case let .provider(id) = scope, !history.providersWithHistory.contains(where: { $0.id == id }) {
            return .all
        }
        return scope
    }

    /// A corner icon opens its pane, or closes it back to usage.
    private func toggle(_ target: Pane) {
        show(pane == target ? .usage : target)
    }

    /// A gauge opens history already scoped to its provider.
    private func showHistory(for providerID: String) {
        historyScope = UsageHistory.Scope.provider(providerID).storedValue
        show(.history)
    }

    private func show(_ target: Pane) {
        withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
            pane = target
        }
        switch target {
        case .settings:
            Analytics.capture(.settingsOpened)
        case .history:
            history.ingestIfStale()
            Analytics.capture(.historyOpened(scope: resolvedScope.storedValue))
        case .usage, .secrets, .alerts:
            break
        }
    }

    /// Fresh data shows nothing here. Data older than a couple of minutes
    /// gets a quiet age line, and a rate-limited provider gets an amber line
    /// naming it and its next retry, so stale numbers never pass as live.
    @ViewBuilder
    private var freshnessFooter: some View {
        let limited = store.entries
            .filter { store.isEnabled($0.id) && $0.state == .rateLimited }
            .compactMap { entry in entry.schedule.retryAt.map { (name: entry.provider.name, retryAt: $0) } }
            .min { $0.retryAt < $1.retryAt }
        if let limited {
            Text(UsageCopy.rateLimitText(providerName: limited.name, retryAt: limited.retryAt))
                .font(.system(size: 10))
                .foregroundStyle(Color(red: 0.85, green: 0.64, blue: 0.26))
        } else if let oldest = activeEntries.compactMap(\.snapshot?.fetchedAt).min(),
                  let text = UsageCopy.freshnessText(fetchedAt: oldest)
        {
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    @ViewBuilder
    private var usageContent: some View {
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
            .onTapGesture { showHistory(for: entry.id) }
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
                    .onTapGesture { showHistory(for: entry.id) }
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

/// Small corner icon, grayish until hovered or active. A tint keeps its
/// colour at every opacity, for the one icon that has to be noticed.
private struct NotchIconButton: View {
    let systemName: String
    var isActive = false
    var tint: Color = .white
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint.opacity(isActive || isHovering ? 0.85 : tint == .white ? 0.35 : 0.7))
                .frame(width: 18, height: 18)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

func paceColor(_ verdict: BurnProjection.Verdict?) -> Color {
    switch verdict {
    case .early: Color(red: 1.0, green: 0.42, blue: 0.34)
    case .onPace: Color(red: 1.0, green: 0.84, blue: 0.04)
    case .plenty: Color(red: 0.2, green: 0.84, blue: 0.29)
    case nil: .white
    }
}

/// Provider logo and name.
struct BrandRow: View {
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
                expectedRemainingFraction: window.expectedRemainingFraction(),
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
/// inside. The small tick across the track marks where the remaining arc
/// should end right now at an even burn: halfway through the window puts it
/// at the bottom of the ring.
struct UsageRing: View {
    let remainingFraction: Double
    var expectedRemainingFraction: Double?
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
            if let expectedRemainingFraction {
                Capsule()
                    .fill(.white.opacity(0.55))
                    .frame(width: 1.5, height: diameter / 12 + 4)
                    .offset(y: -diameter / 2)
                    .rotationEffect(.degrees(expectedRemainingFraction * 360))
            }
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
