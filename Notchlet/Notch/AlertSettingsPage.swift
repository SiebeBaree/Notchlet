import SwiftUI

/// One line per window the notch shows, with a chip per percentage. A lit
/// chip is a rule; tapping it again removes it.
struct AlertSettingsPage: View {
    let store: UsageStore
    let alerts: UsageAlerts
    let back: () -> Void

    private var entries: [UsageStore.Entry] {
        store.entries.filter { store.isEnabled($0.id) && $0.snapshot?.windows.isEmpty == false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HoverTextButton("Back", action: back)
            if entries.isEmpty {
                Text("No usage data yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    BrandRow(provider: entry.provider)
                    ForEach(entry.snapshot?.windows ?? []) { window in
                        HStack(spacing: 8) {
                            Text(window.label)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.leading, 20)
                            Spacer()
                            HStack(spacing: 4) {
                                ForEach(UsageAlertRule.percentChoices, id: \.self) { percent in
                                    let rule = UsageAlertRule(
                                        providerID: entry.id,
                                        windowID: window.id,
                                        percent: percent
                                    )
                                    ThresholdChip(percent: percent, isOn: alerts.isOn(rule)) {
                                        alerts.setRule(rule, on: !alerts.isOn(rule), window: window)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ThresholdChip: View {
    let percent: Int
    let isOn: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text("\(percent)")
                .font(.system(size: 10.5, weight: isOn ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isOn ? .black : .white.opacity(isHovering ? 0.85 : 0.5))
                .frame(width: 34)
                .padding(.vertical, 2)
                .background(
                    isOn ? NotchPalette.amber : .white.opacity(isHovering ? 0.12 : 0.06),
                    in: .capsule
                )
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}
