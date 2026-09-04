import SwiftUI

/// A usage alert, one at a time: the provider, the window's gauge as the
/// usage card draws it, what mark it passed, and Got it. Acknowledging
/// shows the next notice or hands the panel back to usage.
struct AlertsPane: View {
    let alerts: UsageAlerts
    let store: UsageStore

    var body: some View {
        if let notice = alerts.current, let entry = store.entries.first(where: { $0.id == notice.rule.providerID }) {
            // The live window when the store still has this cycle, so the
            // gauge is current rather than frozen at the moment it fired.
            let window = entry.snapshot?.windows.first { $0.id == notice.window.id } ?? notice.window
            let projection = BurnProjection.project(window)
            VStack(alignment: .leading, spacing: 12) {
                BrandRow(provider: entry.provider)
                HStack(spacing: 16) {
                    UsageRing(
                        remainingFraction: window.remainingFraction,
                        expectedRemainingFraction: window.expectedRemainingFraction(),
                        color: paceColor(projection?.verdict),
                        diameter: 62
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(UsageCopy.alertHeadline(windowLabel: window.label, percent: notice.rule.percent))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let reset = UsageCopy.resetText(for: window.resetsAt) {
                            Text(reset)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        if let pace = UsageCopy.paceText(projection: projection, resetsAt: window.resetsAt) {
                            Text(pace)
                                .font(.system(size: 10.5))
                                .foregroundStyle(paceColor(projection?.verdict))
                        }
                    }
                    Spacer(minLength: 0)
                    NotchPillButton("Got it") {
                        withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                            alerts.acknowledge()
                        }
                    }
                }
            }
            // Opens with the panel's own animation, like every other pane;
            // only the swap to the next notice after Got it is a crossfade.
            .id(notice.id)
            .transition(.opacity)
        }
    }
}

/// The one action on an alert: a capsule that lifts on hover and drops
/// back when clicked. Quiet enough to sit in the notch, unmistakable as a
/// button.
struct NotchPillButton: View {
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
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(isHovering ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isHovering ? .white.opacity(0.9) : .white.opacity(0.14), in: .capsule)
                .overlay(Capsule().strokeBorder(.white.opacity(isHovering ? 0 : 0.18), lineWidth: 1))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}
