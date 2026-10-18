import SwiftUI

/// Settings inside the expanded notch. There is no settings window and no
/// menu bar item, so quitting lives here too.
struct NotchSettingsView: View {
    private enum Page: Equatable {
        case main
        case providers
        case provider(String)
        case alerts
    }

    let store: UsageStore
    let updater: UpdateController
    let scanner: SecretScanner
    let alerts: UsageAlerts
    let waits: AgentWaits

    /// The keys Analytics, SecretScanner and UsageStore read.
    @AppStorage("analyticsOptOut") private var analyticsOptOut = false
    @AppStorage(SecretScanner.enabledDefaultsKey) private var secretScanEnabled = true
    @AppStorage(UsageStore.intervalDefaultsKey) private var refreshMinutes = 10
    @AppStorage(UsageRing.timeMarkerDefaultsKey) private var showGaugeTimeMarker = false
    @State private var autoChecksForUpdates: Bool
    /// Mirrors SMAppService, which the system can overrule.
    @State private var startsAtLogin = LoginItem.isEnabled
    @State private var page: Page = .main
    /// Takes the version label's slot until the pane closes.
    @State private var notice: String?

    init(store: UsageStore, updater: UpdateController, scanner: SecretScanner, alerts: UsageAlerts, waits: AgentWaits) {
        self.store = store
        self.updater = updater
        self.scanner = scanner
        self.alerts = alerts
        self.waits = waits
        _autoChecksForUpdates = State(initialValue: updater.automaticallyChecksForUpdates)
    }

    var body: some View {
        switch page {
        case .main:
            mainPage
        case .providers:
            providersPage
        case let .provider(id):
            ProviderSettingsPage(store: store, providerID: id) { show(.providers) }
        case .alerts:
            AlertSettingsPage(store: store, alerts: alerts) { show(.main) }
        }
    }

    private func show(_ page: Page) {
        withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
            self.page = page
        }
    }

    private var providersPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            HoverTextButton("Back") { show(.main) }
            ForEach(store.entries) { entry in
                HStack(spacing: 7) {
                    HStack(spacing: 7) {
                        BrandRow(provider: entry.provider, muted: true)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                        Spacer()
                    }
                    .contentShape(.rect)
                    .onTapGesture { show(.provider(entry.id)) }
                    ProviderToggle(store: store, entry: entry)
                }
            }
            if !store.canEnableMore, store.entries.contains(where: { !store.isEnabled($0.id) }) {
                Text("Up to \(UsageStore.maxActiveProviders) at once. Turn one off to add another.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private var mainPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            linkRow("Providers") { show(.providers) }
            linkRow("Alerts") { show(.alerts) }
            toggleRow(
                "Start at login",
                isOn: Binding(
                    get: { startsAtLogin },
                    set: { enabled in
                        startsAtLogin = LoginItem.setEnabled(enabled)
                        Analytics.capture(.settingChanged(key: "start_at_login", value: String(startsAtLogin)))
                    }
                )
            )
            // System Settings owns this too, so re-read rather than trust
            // what the switch was last set to.
            .onAppear { startsAtLogin = LoginItem.isEnabled }
            toggleRow(
                "Share anonymous usage stats",
                isOn: Binding(
                    get: { !analyticsOptOut },
                    set: { Analytics.setEnabled($0) }
                )
            )
            toggleRow(
                "Automatically check for updates",
                isOn: Binding(
                    get: { autoChecksForUpdates },
                    set: { enabled in
                        autoChecksForUpdates = enabled
                        updater.automaticallyChecksForUpdates = enabled
                        Analytics.capture(.settingChanged(key: "auto_check_updates", value: String(enabled)))
                    }
                )
            )
            toggleRow(
                "Scan chats for leaked secrets",
                tip: scanner.isAvailable ? Self
                    .secretScanTip(providerNames: scannedProviderNames) : "Needs Apple silicon",
                isOn: Binding(
                    get: { secretScanEnabled && scanner.isAvailable },
                    set: { enabled in
                        secretScanEnabled = enabled
                        scanner.setEnabled(enabled)
                    }
                )
            )
            .disabled(!scanner.isAvailable)
            // A tip drops over the rows below it, so each row with one
            // sits above the next.
            .zIndex(2)
            toggleRow(
                "Show when an agent needs you",
                tip: Self.agentWaitTip,
                isOn: Binding(
                    get: { waits.isEnabled },
                    set: { waits.setEnabled($0) }
                )
            )
            .zIndex(1)
            toggleRow(
                "Show time marker on gauges",
                tip: "Marks how much of your limit would be left with even usage until reset. "
                    + "Halfway through a 5-hour limit, the marker sits at 50%, at the bottom of the gauge.",
                isOn: $showGaugeTimeMarker
            )
            .zIndex(0.5)
            HStack {
                Text("Refresh every")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                // Segmented, not a menu: a popup menu is its own window, and
                // the notch reads the cursor moving into it as leaving the
                // panel, which collapses it and drops the settings pane.
                Picker("Refresh every", selection: $refreshMinutes) {
                    ForEach(UsageStore.intervalChoicesMinutes, id: \.self) { minutes in
                        Text("\(minutes)m").tag(minutes)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
                .onChange(of: refreshMinutes) { _, minutes in
                    store.reschedule()
                    Analytics.capture(.settingChanged(key: "refresh_interval_minutes", value: String(minutes)))
                }
            }

            #if DEBUG
                HStack(spacing: 10) {
                    Text("Fire")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    ForEach(DebugTrigger.allCases, id: \.self) { trigger in
                        HoverTextButton(trigger.title) { fire(trigger) }
                    }
                }
            #endif

            NotchRule()

            // The only way out: the panel never activates, so Cmd+Q never
            // reaches us.
            HStack(spacing: 14) {
                if let version = updater.availableUpdateVersion {
                    Text("Version \(version) available")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white)
                    Spacer()
                    HoverTextButton("Quit") {
                        NSApp.terminate(nil)
                    }
                    Button("Install") {
                        updater.installAvailableUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Text(notice ?? versionText)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    HoverTextButton("Quit") {
                        NSApp.terminate(nil)
                    }
                    HoverTextButton("Check for updates") {
                        if DeviceInfo.isDevelopment {
                            notice = "Development builds cannot check for updates"
                        } else {
                            updater.checkForUpdates()
                        }
                    }
                }
            }
        }
    }

    private var versionText: String {
        DeviceInfo.isDevelopment ? "Notchlet Development" : "Notchlet \(DeviceInfo.appVersion)"
    }

    private var scannedProviderNames: [String] {
        store.entries.filter { $0.provider.secrets != nil }.map(\.provider.name)
    }

    static func secretScanTip(providerNames: [String]) -> String {
        let hours = Int(SecretScanSchedule.interval / 3600)
        let cadence = hours == 1 ? "every hour" : "every \(hours) hours"
        let chats = providerNames.isEmpty ? "your chats" : "your \(providerNames.joined(separator: " and ")) chats"
        return "Runs betterleaks over \(chats) on this Mac, once the Mac has been idle for two minutes and then "
            + "\(cadence) over what changed. Nothing leaves the Mac."
    }

    static let agentWaitTip = "Draws a line around the notch while an agent waits on you. Blue means it finished "
        + "its turn, amber means it is asking for permission or an answer. Hovering, switching back to its terminal "
        + "or sending the next prompt clears it."

    #if DEBUG
        /// Three seconds is time to move the mouse out: a notification
        /// waits for the hover to end, and a wait only outlines a closed
        /// notch.
        private func fire(_ trigger: DebugTrigger) {
            notice = "\(trigger.title) fires in 3s, move the mouse out"
            let targets = DebugTrigger.Targets(store: store, scanner: scanner, alerts: alerts, waits: waits)
            Task {
                try? await Task.sleep(for: .seconds(3))
                trigger.fire(targets)
            }
        }
    #endif

    private func linkRow(_ label: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
        }
        .contentShape(.rect)
        .onTapGesture(perform: action)
    }

    private func toggleRow(_ label: String, tip: String? = nil, isOn: Binding<Bool>) -> some View {
        ToggleRow(label: label, tip: tip, isOn: isOn)
    }
}

/// A switch with its label and, when there is more to say, an info icon
/// whose explanation drops in under the row while hovered. Drawn inside
/// the notch rather than as a system tooltip, which is its own window and
/// slow to appear. The tip is always in the tree and only fades: inserting
/// a view rebuilds the hover tracking under the cursor, which ended the
/// hover the moment it began.
private struct ToggleRow: View {
    let label: String
    let tip: String?
    let isOn: Binding<Bool>

    @State private var showsTip = false
    @State private var rowHeight: CGFloat = 0

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.85))
            if tip != nil {
                Image(systemName: "info.circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(showsTip ? 0.85 : 0.4))
                    .frame(width: 14, height: 14)
                    .contentShape(.rect)
                    .onHover { showsTip = $0 }
            }
            Spacer()
            Toggle(label, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
        .overlay(alignment: .topLeading) {
            if let tip {
                Text(tip)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(width: 300, alignment: .leading)
                    .background(Color(white: 0.16), in: .rect(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.14)))
                    .opacity(showsTip ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: showsTip)
                    .allowsHitTesting(false)
                    // An offset rather than an alignment guide: the guide
                    // held for the first row and not the second, which hung
                    // its tip upward over the rows above.
                    .offset(y: rowHeight + 6)
            }
        }
    }
}

/// Locked when the cap is reached.
struct ProviderToggle: View {
    let store: UsageStore
    let entry: UsageStore.Entry

    var body: some View {
        Toggle(entry.provider.name, isOn: Binding(
            get: { store.isEnabled(entry.id) },
            set: { enabled in
                store.setEnabled(entry.id, enabled)
                Analytics.capture(.settingChanged(key: "provider_\(entry.id)_enabled", value: String(enabled)))
            }
        ))
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.mini)
        .disabled(!store.isEnabled(entry.id) && !store.canEnableMore)
    }
}
