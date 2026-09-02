import SwiftUI

/// Settings, rendered inside the expanded notch. There is no settings
/// window and no menu bar item; the notch is the whole surface, so quitting
/// lives here too. The providers row opens a sub-page with one visibility
/// toggle per provider; at the cap the remaining toggles lock until one is
/// turned off.
struct NotchSettingsView: View {
    let store: UsageStore
    let updater: UpdateController

    /// Same key Analytics uses; @AppStorage keeps the toggle in sync with it.
    @AppStorage("analyticsOptOut") private var analyticsOptOut = false
    // Same key UsageStore reads for its closed-panel poll cadence.
    @AppStorage(UsageStore.intervalDefaultsKey) private var refreshMinutes = 10
    @State private var autoChecksForUpdates: Bool
    @State private var showingProviders = false

    init(store: UsageStore, updater: UpdateController) {
        self.store = store
        self.updater = updater
        _autoChecksForUpdates = State(initialValue: updater.automaticallyChecksForUpdates)
    }

    var body: some View {
        if showingProviders {
            providersPage
        } else {
            mainPage
        }
    }

    private var providersPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            HoverTextButton("Back") {
                withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                    showingProviders = false
                }
            }
            ForEach(store.entries) { entry in
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
                    Spacer()
                    Toggle(entry.provider.name, isOn: Binding(
                        get: { store.isEnabled(entry.id) },
                        set: { enabled in
                            store.setEnabled(entry.id, enabled)
                            Analytics.capture(.settingChanged(
                                key: "provider_\(entry.id)_enabled",
                                value: String(enabled)
                            ))
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(!store.isEnabled(entry.id) && !store.canEnableMore)
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
            .onTapGesture {
                withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                    showingProviders = true
                }
            }
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
