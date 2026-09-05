import SwiftUI

/// One usage alert at a time; Got it shows the next or hands the panel
/// back to usage.
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
                        color: NotchPalette.pace(projection?.verdict),
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
                                .foregroundStyle(NotchPalette.pace(projection?.verdict))
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
