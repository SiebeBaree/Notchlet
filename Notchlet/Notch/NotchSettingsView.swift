import SwiftUI

/// Settings, rendered inside the expanded notch. There is no settings
/// window and no menu bar item; the notch is the whole surface.
struct NotchSettingsView: View {
    let updater: UpdateController

    // Same key Analytics uses; @AppStorage keeps the toggle in sync with it.
    @AppStorage("analyticsOptOut") private var analyticsOptOut = false
    @State private var autoChecksForUpdates: Bool

    init(updater: UpdateController) {
        self.updater = updater
        _autoChecksForUpdates = State(initialValue: updater.automaticallyChecksForUpdates)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(height: 1)

            HStack {
                if let version = updater.availableUpdateVersion {
                    Text("Version \(version) available")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white)
                    Spacer()
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
