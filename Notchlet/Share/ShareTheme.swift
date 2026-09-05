import SwiftUI

/// The background, the glass and the colours the content and graphs use.
struct ShareTheme {
    let id: ShareThemeID
    let name: String
    let isDark: Bool
    let text: Color
    let muted: Color
    let faint: Color
    let rule: Color
    let graph: GraphStyle
    let bar: Color
    let barFill: Color
    let glassFill: [Gradient.Stop]
    let inner: [Gradient.Stop]
    let innerWidth: CGFloat
    let rim: [Gradient.Stop]
    let rimWidth: CGFloat
    let bounce: Color
    let sheen: Double
    let shadow: Color
    /// Top and bottom of the editor's swatch.
    let swatch: [Color]

    @ViewBuilder
    var background: some View {
        let diagonal = ShareCardView.size.width * 0.81
        switch id {
        case .notch:
            LinearGradient(
                colors: [Color(hex: 0x8CEBFF), Color(hex: 0x1FB6E8), Color(hex: 0x0A5A9C)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                stops: [
                    .init(color: .white.opacity(0.45), location: 0),
                    .init(color: .white.opacity(0.08), location: 0.45),
                    .init(color: .white.opacity(0), location: 1),
                ],
                center: UnitPoint(x: 0.25, y: 0),
                startRadius: 0,
                endRadius: diagonal * 0.9
            )
        case .midnight:
            Color(hex: 0x08080C)
            wash(0x6A5BFF, opacity: 0.55, at: UnitPoint(x: 0.15, y: 0.1), radius: diagonal * 0.6)
            wash(0x22D3EE, opacity: 0.38, at: UnitPoint(x: 0.9, y: 0.95), radius: diagonal * 0.6)
            wash(0xFF5BA6, opacity: 0.22, at: UnitPoint(x: 0.75, y: 0.05), radius: diagonal * 0.4)
        case .paper:
            Color(hex: 0xEEF0F5)
            wash(0x9CD1FF, opacity: 0.9, at: UnitPoint(x: 0.1, y: 0), radius: diagonal * 0.7)
            wash(0xFFC9A8, opacity: 0.9, at: UnitPoint(x: 0.95, y: 1), radius: diagonal * 0.7)
        }
    }

    private func wash(_ hex: UInt, opacity: Double, at center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(
            colors: [Color(hex: hex, opacity: opacity), Color(hex: hex, opacity: 0)],
            center: center,
            startRadius: 0,
            endRadius: radius
        )
    }

    static func theme(_ id: ShareThemeID) -> ShareTheme {
        switch id {
        case .notch: notch
        case .midnight: midnight
        case .paper: paper
        }
    }

    /// The app icon's look: black glass on the blue slab.
    static let notch = ShareTheme(
        id: .notch,
        name: "Notch",
        isDark: true,
        text: .white,
        muted: .white.opacity(0.55),
        faint: .white.opacity(0.32),
        rule: .white.opacity(0.14),
        graph: GraphStyle(
            levels: [Color(hex: 0x123F7A), Color(hex: 0x1F5EAD), Color(hex: 0x3887E6), Color(hex: 0x87B5F0)],
            empty: .white.opacity(0.07),
            unknown: .white.opacity(0.03),
            line: Color(hex: 0x3887E6),
            text: .white.opacity(0.55),
            rule: .white.opacity(0.14),
            labelSize: 12
        ),
        bar: .white.opacity(0.10),
        barFill: Color(hex: 0x3887E6),
        glassFill: [
            .init(color: Color(hex: 0x050509), location: 0),
            .init(color: Color(hex: 0x0C0C14), location: 0.6),
            .init(color: Color(hex: 0x1B1A2E), location: 1),
        ],
        inner: [
            .init(color: .white.opacity(0.14), location: 0),
            .init(color: Color(hex: 0x5FC8F0, opacity: 0.08), location: 0.5),
            .init(color: Color(hex: 0x7FDCFF, opacity: 0.26), location: 1),
        ],
        innerWidth: 40,
        rim: [
            .init(color: .white.opacity(0.85), location: 0),
            .init(color: .white.opacity(0.22), location: 0.3),
            .init(color: Color(hex: 0xBFF1FF, opacity: 0.25), location: 0.7),
            .init(color: Color(hex: 0xCDF4FF, opacity: 0.8), location: 1),
        ],
        rimWidth: 2.5,
        bounce: Color(hex: 0x3FBFF0, opacity: 0.4),
        sheen: 0.16,
        shadow: Color(hex: 0x043457, opacity: 0.55),
        swatch: [Color(hex: 0x8CEBFF), Color(hex: 0x0A5A9C)]
    )

    /// Dark glass over a near-black field with two soft washes.
    static let midnight = ShareTheme(
        id: .midnight,
        name: "Midnight",
        isDark: true,
        text: .white,
        muted: .white.opacity(0.55),
        faint: .white.opacity(0.32),
        rule: .white.opacity(0.14),
        graph: GraphStyle(
            levels: [Color(hex: 0x2C2A6E), Color(hex: 0x4842AE), Color(hex: 0x7A78F2), Color(hex: 0xB7B9FF)],
            empty: .white.opacity(0.07),
            unknown: .white.opacity(0.03),
            line: Color(hex: 0x8B8CFF),
            text: .white.opacity(0.55),
            rule: .white.opacity(0.14),
            labelSize: 12
        ),
        bar: .white.opacity(0.10),
        barFill: Color(hex: 0x7A78F2),
        glassFill: [
            .init(color: .white.opacity(0.10), location: 0),
            .init(color: .white.opacity(0.04), location: 1),
        ],
        inner: [
            .init(color: .white.opacity(0.12), location: 0),
            .init(color: .white.opacity(0.02), location: 1),
        ],
        innerWidth: 28,
        rim: [
            .init(color: .white.opacity(0.55), location: 0),
            .init(color: .white.opacity(0.12), location: 0.5),
            .init(color: .white.opacity(0.3), location: 1),
        ],
        rimWidth: 1.5,
        bounce: Color(hex: 0x22D3EE, opacity: 0.12),
        sheen: 0.16,
        shadow: .black.opacity(0.6),
        swatch: [Color(hex: 0x3B2F8F), Color(hex: 0x0F2A33)]
    )

    /// White glass for light timelines.
    static let paper = ShareTheme(
        id: .paper,
        name: "Paper",
        isDark: false,
        text: Color(hex: 0x111114),
        muted: Color(hex: 0x111114, opacity: 0.55),
        faint: Color(hex: 0x111114, opacity: 0.35),
        rule: .black.opacity(0.12),
        graph: GraphStyle(
            levels: [Color(hex: 0xBFDCFF), Color(hex: 0x7DB6FF), Color(hex: 0x2F86F6), Color(hex: 0x0B5ED7)],
            empty: .black.opacity(0.06),
            unknown: .black.opacity(0.025),
            line: Color(hex: 0x2F86F6),
            text: Color(hex: 0x111114, opacity: 0.55),
            rule: .black.opacity(0.12),
            labelSize: 12
        ),
        bar: .black.opacity(0.07),
        barFill: Color(hex: 0x2F86F6),
        glassFill: [
            .init(color: .white.opacity(0.78), location: 0),
            .init(color: .white.opacity(0.6), location: 1),
        ],
        inner: [
            .init(color: .white.opacity(0.9), location: 0),
            .init(color: .white.opacity(0.2), location: 1),
        ],
        innerWidth: 28,
        rim: [
            .init(color: .white, location: 0),
            .init(color: .black.opacity(0.10), location: 1),
        ],
        rimWidth: 1.5,
        bounce: Color(hex: 0xFFC9A8, opacity: 0.25),
        sheen: 0.5,
        shadow: Color(hex: 0x2B3A55, opacity: 0.22),
        swatch: [Color(hex: 0xDBEEFF), Color(hex: 0xFFD9C2)]
    )
}

extension Color {
    /// `Color(hex: 0x3887E6)`, sRGB.
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
