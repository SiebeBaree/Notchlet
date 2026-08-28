import SwiftUI

/// Root view of the panel. Renders the black notch shape and expands it into
/// a card on hover.
///
/// Known limitation of the skeleton: the hosting window is always
/// `NotchGeometry.panelSize`, so the transparent area around the collapsed
/// shape still swallows clicks. Fixing hit-testing (click-through for
/// transparent pixels) is on the roadmap.
struct NotchView: View {
    let store: UsageStore
    let notchSize: CGSize

    @State private var isExpanded = false

    private var expandedSize: CGSize {
        CGSize(width: max(notchSize.width + 220, 420), height: 180)
    }

    var body: some View {
        VStack(spacing: 0) {
            shape
                .onHover { hovering in
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                        isExpanded = hovering
                    }
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .task {
            await store.refresh()
        }
    }

    private var shape: some View {
        ZStack(alignment: .top) {
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(
            width: isExpanded ? expandedSize.width : notchSize.width,
            height: isExpanded ? expandedSize.height : notchSize.height
        )
        .background(
            .black,
            in: .rect(bottomLeadingRadius: isExpanded ? 20 : 10, bottomTrailingRadius: isExpanded ? 20 : 10)
        )
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Leave room for the physical notch cutout.
            Spacer().frame(height: notchSize.height)

            ForEach(store.entries) { entry in
                UsageRow(entry: entry)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One provider's usage at a glance.
private struct UsageRow: View {
    let entry: UsageStore.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.provider.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            if let snapshot = entry.snapshot {
                UsageBar(label: "5h", window: snapshot.fiveHour)
                UsageBar(label: "Week", window: snapshot.weekly)
            } else {
                Text("No data yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

private struct UsageBar: View {
    let label: String
    let window: UsageWindow?

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 32, alignment: .leading)
            ProgressView(value: window?.usedFraction ?? 0)
                .tint(.white)
        }
    }
}
