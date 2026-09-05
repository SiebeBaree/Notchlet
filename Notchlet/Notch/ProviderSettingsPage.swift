import SwiftUI

/// One provider's page: its toggle, the sign-in picker when it has more
/// than one way in, a status line, and a paste row per option that takes a
/// secret. Pasting reads the clipboard rather than opening a text field:
/// typing a token into a notch is no fun, and a button needs no keyboard
/// focus.
struct ProviderSettingsPage: View {
    let store: UsageStore
    let providerID: String
    let back: () -> Void

    /// Seeded in `init` rather than `onAppear`: a state change on appear
    /// would fire `onChange`, which rewrites the setting, refetches and logs
    /// a change that never happened.
    @State private var selection: AuthSelection
    @State private var storedSecrets: Set<String>
    @State private var notice: String?

    init(store: UsageStore, providerID: String, back: @escaping () -> Void) {
        self.store = store
        self.providerID = providerID
        self.back = back
        let options = store.entries.first { $0.id == providerID }?.provider.authOptions ?? []
        _selection = State(initialValue: ProviderAuthSettings.selection(for: providerID, options: options))
        _storedSecrets = State(initialValue: Set(options.filter {
            PastedSecrets.hasSecret(providerID: providerID, optionID: $0.id)
        }.map(\.id)))
    }

    private var entry: UsageStore.Entry? {
        store.entries.first { $0.id == providerID }
    }

    var body: some View {
        if let entry {
            let provider = entry.provider
            VStack(alignment: .leading, spacing: 10) {
                HoverTextButton("Back", action: back)
                HStack(spacing: 7) {
                    BrandRow(provider: provider)
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
                                value: selection.rawValue
                            ))
                        }
                    }
                }
                Text(statusText(for: entry))
                    .font(.system(size: 10))
                    .foregroundStyle(isProblem(entry.state) ? NotchPalette.amber : .white.opacity(0.5))
                ForEach(provider.authOptions.filter { $0.secretName != nil }) { option in
                    secretRow(option)
                }
                if let notice {
                    Text(notice)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }

    private func isProblem(_ state: UsageStore.ProviderState?) -> Bool {
        if case .notAvailable = state {
            return true
        }
        return false
    }

    private func statusText(for entry: UsageStore.Entry) -> String {
        UsageCopy.providerStatusText(
            state: entry.state,
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
                        guard await PastedSecrets.remove(providerID: providerID, optionID: option.id) else {
                            notice = "Could not remove the \(secretName) from the keychain"
                            return
                        }
                        storedSecrets.remove(option.id)
                        notice = nil
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
            if await PastedSecrets.save(text, providerID: providerID, optionID: option.id) {
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
