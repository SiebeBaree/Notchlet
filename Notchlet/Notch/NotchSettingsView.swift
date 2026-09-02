import SwiftUI

/// Settings, rendered inside the expanded notch. There is no settings
/// window and no menu bar item; the notch is the whole surface, so quitting
/// lives here too. The providers row opens a list with one visibility
/// toggle per provider; at the cap the remaining toggles lock until one is
/// turned off. Each provider row opens its own page: how it signs in, how
/// that is going, and a place to paste a secret where the provider takes
/// one.
struct NotchSettingsView: View {
    private enum Page: Equatable {
        case main
        case providers
        case provider(String)
    }

    let store: UsageStore
    let updater: UpdateController

    /// Same key Analytics uses; @AppStorage keeps the toggle in sync with it.
    @AppStorage("analyticsOptOut") private var analyticsOptOut = false
    // Same key UsageStore reads for its closed-panel poll cadence.
    @AppStorage(UsageStore.intervalDefaultsKey) private var refreshMinutes = 10
    @State private var autoChecksForUpdates: Bool
    @State private var page: Page = .main

    init(store: UsageStore, updater: UpdateController) {
        self.store = store
        self.updater = updater
        _autoChecksForUpdates = State(initialValue: updater.automaticallyChecksForUpdates)
    }

    var body: some View {
        switch page {
        case .main:
            mainPage
        case .providers:
            providersPage
        case let .provider(id):
            ProviderPage(store: store, providerID: id) { show(.providers) }
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
                        Image(entry.provider.logoAssetName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                            .foregroundStyle(.white.opacity(0.85))
                        Text(entry.provider.name)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.85))
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
            HStack {
                Text("Providers")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .contentShape(.rect)
            .onTapGesture { show(.providers) }
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

            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(height: 1)

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
private struct ProviderToggle: View {
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

/// One provider's page: its toggle, the sign-in picker when it has more
/// than one way in, a status line, and a paste row per option that takes a
/// secret. Pasting reads the clipboard rather than opening a text field:
/// typing a token into a notch is no fun, and a button needs no keyboard
/// focus.
private struct ProviderPage: View {
    let store: UsageStore
    let providerID: String
    let back: () -> Void

    @State private var selection: AuthSelection = .auto
    @State private var storedSecrets: Set<String> = []
    @State private var notice: String?

    private static let problemColor = Color(red: 0.85, green: 0.64, blue: 0.26)

    private var entry: UsageStore.Entry? {
        store.entries.first { $0.id == providerID }
    }

    var body: some View {
        if let entry {
            let provider = entry.provider
            VStack(alignment: .leading, spacing: 10) {
                HoverTextButton("Back", action: back)
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
                    Spacer()
                    ProviderToggle(store: store, entry: entry)
                }
                if provider.authOptions.count > 1 {
                    HStack {
                        Text("Sign in with")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Picker("Sign in with", selection: $selection) {
                            Text("Auto").tag(AuthSelection.auto)
                            ForEach(provider.authOptions) { option in
                                Text(option.label).tag(AuthSelection.option(option.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .fixedSize()
                        .onChange(of: selection) { _, selection in
                            ProviderAuthSettings.setSelection(selection, for: providerID)
                            store.refreshNow(providerID)
                            Analytics.capture(.settingChanged(
                                key: "provider_\(providerID)_auth",
                                value: selection.storedValue
                            ))
                        }
                    }
                }
                Text(statusText(for: entry))
                    .font(.system(size: 10))
                    .foregroundStyle(entry.state == .notAvailable ? Self.problemColor : .white.opacity(0.5))
                ForEach(provider.authOptions.filter { $0.secretName != nil }) { option in
                    secretRow(option)
                }
                if let notice {
                    Text(notice)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .onAppear {
                selection = ProviderAuthSettings.selection(for: providerID, options: provider.authOptions)
                storedSecrets = Set(provider.authOptions.filter {
                    SecretStore.hasSecret(providerID: providerID, optionID: $0.id)
                }.map(\.id))
            }
        }
    }

    private func statusText(for entry: UsageStore.Entry) -> String {
        UsageCopy.providerStatusText(
            state: entry.state,
            problem: entry.authProblem,
            option: entry.provider.authOptions.first { $0.id == entry.snapshot?.authOptionID },
            signInHint: entry.provider.signInHint,
            retryAt: entry.schedule.retryAt
        )
    }

    private func secretRow(_ option: AuthOption) -> some View {
        let secretName = option.secretName ?? "secret"
        return HStack {
            if storedSecrets.contains(option.id) {
                Text("\(secretName.prefix(1).uppercased() + secretName.dropFirst()) saved")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                HoverTextButton("Remove") {
                    Task {
                        await SecretStore.remove(providerID: providerID, optionID: option.id)
                        storedSecrets.remove(option.id)
                        store.refreshNow(providerID)
                        Analytics.capture(.settingChanged(
                            key: "provider_\(providerID)_secret_\(option.id)",
                            value: "removed"
                        ))
                    }
                }
            } else {
                Text("Copy your \(secretName), then")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                HoverTextButton("Paste \(secretName)") {
                    paste(option, secretName: secretName)
                }
            }
        }
    }

    private func paste(_ option: AuthOption, secretName: String) {
        let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            notice = "Nothing on the clipboard"
            return
        }
        Task {
            if await SecretStore.save(text, providerID: providerID, optionID: option.id) {
                storedSecrets.insert(option.id)
                notice = nil
                store.refreshNow(providerID)
                Analytics.capture(.settingChanged(
                    key: "provider_\(providerID)_secret_\(option.id)",
                    value: "saved"
                ))
            } else {
                notice = "Could not save the \(secretName) to the keychain"
            }
        }
    }
}

/// Quiet text button that brightens on hover.
private struct HoverTextButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(isHovering ? 0.85 : 0.45))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
