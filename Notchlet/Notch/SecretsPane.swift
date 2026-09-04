import SwiftUI

/// The secrets pane: one leaked key at a time, newest first. What kind of
/// key betterleaks thinks it is, the line of the chat it sits in with the
/// key masked to its preview, and the three things to do about it. A pager
/// in the header walks the rest.
struct SecretsPane: View {
    static let amber = Color(red: 0.85, green: 0.64, blue: 0.26)

    let scanner: SecretScanner

    @State private var index = 0

    var body: some View {
        let pending = scanner.pending
        VStack(alignment: .leading, spacing: 12) {
            if pending.isEmpty {
                Text(Self.statusText(scanner.status) ?? "No leaked secrets pending")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                let current = min(index, pending.count - 1)
                let finding = pending[current]
                header(pending: pending, current: current)
                Text(finding.kind)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                contextLine(finding)
                actions(finding, pending: pending)
            }
        }
    }

    private func header(pending: [SecretFinding], current: Int) -> some View {
        HStack {
            Text(Self.title(count: pending.count, providerName: providerName(pending)))
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            if pending.count > 1 {
                HStack(spacing: 6) {
                    PagerButton(systemName: "chevron.left", isEnabled: current > 0) { index = current - 1 }
                    Text("\(current + 1) of \(pending.count)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.55))
                        .monospacedDigit()
                    PagerButton(systemName: "chevron.right", isEnabled: current < pending.count - 1) {
                        index = current + 1
                    }
                }
            }
        }
    }

    /// The preview stands out in amber inside the line it was found on.
    private func contextLine(_ finding: SecretFinding) -> some View {
        var text = AttributedString(finding.context)
        if let range = text.range(of: finding.preview) {
            text[range].foregroundColor = Self.amber
        }
        return Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 6))
    }

    /// Reporting needs analytics on to go anywhere, so the button only
    /// exists while it does; Ignore is always there.
    private func actions(_ finding: SecretFinding, pending: [SecretFinding]) -> some View {
        HStack(spacing: 12) {
            Button("How to solve this") {
                scanner.openHelp(finding.id)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            HoverTextButton("Ignore") {
                scanner.ignore(finding.id)
            }
            if Analytics.isEnabled {
                HoverTextButton("Report false positive") {
                    scanner.reportFalsePositive(finding.id)
                }
            }
            Spacer()
            if pending.count > 1 {
                HoverTextButton("Ignore all \(pending.count)") {
                    scanner.ignoreAll()
                }
            }
        }
    }

    /// The provider's name when every pending finding is from one.
    private func providerName(_ pending: [SecretFinding]) -> String? {
        let ids = Set(pending.map(\.providerID))
        guard ids.count == 1, let id = ids.first else { return nil }
        return scanner.providerName(id)
    }

    static func title(count: Int, providerName: String?) -> String {
        let noun = count == 1 ? "leaked secret" : "leaked secrets"
        let place = providerName.map { "\($0) chats" } ?? "your chats"
        return "\(count) \(noun) in \(place)"
    }

    /// One line on what the scanner is doing, for the empty pane, the
    /// settings page and the spinner's tooltip. Nil when it is off.
    static func statusText(_ status: SecretScanner.Status, now: Date = .now) -> String? {
        switch status {
        case .off, .unavailable:
            nil
        case .waitingForIdle:
            "First scan starts once the Mac has been idle for two minutes and takes a few minutes"
        case .scanning:
            "Scanning your chats for leaked secrets, results in a few minutes"
        case .failed:
            "Last scan failed, retrying within five minutes"
        case let .scanned(date):
            "Last scan \(Self.relative.localizedString(for: date, relativeTo: now))"
        }
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

private struct PagerButton: View {
    let systemName: String
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(isHovering ? 0.85 : 0.45))
                .frame(width: 14, height: 14)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.3)
        .onHover { isHovering = $0 }
    }
}
