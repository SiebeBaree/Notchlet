import SwiftUI

/// Settings, rendered inside the expanded notch. There is no settings
/// window and no menu bar item; the notch is the whole surface, so quitting
/// lives here too. The providers row opens a list with one visibility
/// toggle per provider; at the cap the remaining toggles lock until one is
/// turned off. Each provider row opens its own page: how it signs in, how
/// that is going, and a place to paste a secret where the provider takes
/// one. The alerts row opens one line per window the notch shows, with a
/// chip per threshold. The agent switch hooks Notchlet into the CLIs, or
/// takes those hooks out again.
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

    /// Same key Analytics uses; @AppStorage keeps the toggle in sync with it.
    @AppStorage("analyticsOptOut") private var analyticsOptOut = false
    /// Same key SecretScanner reads; it owns the loop, this owns the switch.
    @AppStorage(SecretScanner.enabledDefaultsKey) private var secretScanEnabled = true
    // Same key UsageStore reads for its closed-panel poll cadence.
    @AppStorage(UsageStore.intervalDefaultsKey) private var refreshMinutes = 10
    @State private var autoChecksForUpdates: Bool
    @State private var page: Page = .main

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
                isOn: Binding(
                    get: { secretScanEnabled && scanner.isAvailable },
                    set: { enabled in
                        secretScanEnabled = enabled
                        scanner.setEnabled(enabled)
                    }
                )
            )
            .disabled(!scanner.isAvailable)
            if let status = scanner.isAvailable ? SecretsPane.statusText(scanner.status) : "Needs Apple silicon" {
                Text(status)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, -6)
            }
            toggleRow(
                "Show when an agent needs you",
                isOn: Binding(
                    get: { waits.isEnabled },
                    set: { waits.setEnabled($0) }
                )
            )
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

            NotchRule()

            // The only way out of the app: no dock icon, no menu bar item,
            // and the panel never activates, so Cmd+Q never reaches us.
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
                    Text("Notchlet \(DeviceInfo.appVersion)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    HoverTextButton("Quit") {
                        NSApp.terminate(nil)
                    }
                    HoverTextButton("Check for updates") {
                        updater.checkForUpdates()
                    }
                }
            }
        }
    }

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

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Toggle(label, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

/// A provider's visibility switch, locked when the cap is reached.
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
