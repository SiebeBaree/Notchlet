import SwiftUI

enum NotchPalette {
    /// Attention: a leaked key, a lit alert chip, a rate-limited provider.
    static let amber = Color(red: 0.85, green: 0.64, blue: 0.26)
    static let rule = Color.white.opacity(0.15)

    static func pace(_ verdict: BurnProjection.Verdict?) -> Color {
        switch verdict {
        case .early: Color(red: 1.0, green: 0.42, blue: 0.34)
        case .onPace: Color(red: 1.0, green: 0.84, blue: 0.04)
        case .plenty: Color(red: 0.2, green: 0.84, blue: 0.29)
        case nil: .white
        }
    }
}

struct NotchRule: View {
    var body: some View {
        Rectangle()
            .fill(NotchPalette.rule)
            .frame(height: 1)
    }
}

/// `muted` is the settings list's quieter row.
struct BrandRow: View {
    let provider: any UsageProvider
    var muted = false

    var body: some View {
        HStack(spacing: 7) {
            Image(provider.logoAssetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: muted ? 12 : 13, height: muted ? 12 : 13)
            Text(provider.name)
                .font(.system(size: muted ? 11.5 : 12, weight: muted ? .regular : .semibold))
        }
        .foregroundStyle(.white.opacity(muted ? 0.85 : 1))
    }
}

/// The tick across the track marks where the remaining arc should end right
/// now at an even burn.
struct UsageRing: View {
    let remainingFraction: Double
    var expectedRemainingFraction: Double?
    let color: Color
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.17), lineWidth: diameter / 12)
            Circle()
                .trim(from: 0, to: remainingFraction)
                .stroke(color, style: StrokeStyle(lineWidth: diameter / 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let expectedRemainingFraction {
                Capsule()
                    .fill(.white.opacity(0.55))
                    .frame(width: 1.5, height: diameter / 12 + 4)
                    .offset(y: -diameter / 2)
                    .rotationEffect(.degrees(expectedRemainingFraction * 360))
            }
            VStack(spacing: -2) {
                Text("\(Int((remainingFraction * 100).rounded()))%")
                    .font(.system(size: diameter * 0.23, weight: .semibold))
                    .foregroundStyle(.white)
                Text("left")
                    .font(.system(size: diameter * 0.11))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Brightens on hover, or stays bright while it is the active choice.
struct HoverTextButton: View {
    let title: String
    var isActive = false
    let action: () -> Void

    @State private var isHovering = false

    init(_ title: String, isActive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isActive = isActive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(isActive || isHovering ? 0.85 : 0.45))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// The one action on an alert.
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

/// A tint keeps its colour at every opacity, for the one icon that has to
/// be noticed.
struct NotchIconButton: View {
    let systemName: String
    var isActive = false
    var tint: Color = .white
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint.opacity(isActive || isHovering ? 0.85 : tint == .white ? 0.35 : 0.7))
                .frame(width: 18, height: 18)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct ScopeChips: View {
    let providers: [any UsageProvider]
    @Binding var scope: UsageHistory.Scope
    var size: CGFloat = 10.5

    var body: some View {
        HStack(spacing: 4) {
            chip("All", scope: .all)
            ForEach(providers, id: \.id) { provider in
                chip(provider.name, scope: .provider(provider.id))
            }
        }
    }

    private func chip(_ title: String, scope: UsageHistory.Scope) -> some View {
        let isOn = self.scope == scope
        return Button {
            withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                self.scope = scope
            }
        } label: {
            Text(title)
                .font(.system(size: size))
                .foregroundStyle(isOn ? .white : .white.opacity(0.55))
                .padding(.horizontal, size * 0.8)
                .padding(.vertical, size * 0.2)
                .background(isOn ? .white.opacity(0.12) : .clear, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}
