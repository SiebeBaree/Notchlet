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
                    color: waits.needsInput ? NSColor(NotchPalette.amber) : .systemBlue,
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
                UsagePane(store: store, focusedProviderID: $focusedProviderID, showHistory: showHistory)
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
                NotchIconButton(systemName: "key.fill", isActive: pane == .secrets, tint: NotchPalette.amber) {
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
}
