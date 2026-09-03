import AppKit
import SwiftUI

/// The shared image, 1200 by 675 points, drawn from a `ShareCard`. The
/// editor shows this view scaled down and `ShareRenderer` renders it at 2x,
/// so there is one layout to get right.
///
/// The glass is painted, never sampled: `ImageRenderer` has no window
/// behind the view for a material to blur, so every highlight here is a
/// gradient. Nothing in this file may use a material or a blur.
struct ShareCardView: View {
    static let size = CGSize(width: 1200, height: 675)
    /// Canvas edge to glass edge.
    static let inset: CGFloat = 44
    /// Glass edge to content.
    static let padding: CGFloat = 56
    static let contentWidth = size.width - 2 * (inset + padding)

    let card: ShareCard
    let theme: ShareTheme
    let calendar: Calendar

    var body: some View {
        ZStack {
            theme.background
            ShareGlass(theme: theme)
                .padding(Self.inset)
            content
                .padding(Self.inset)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Below the bezel, level with the bottom of the notch.
            header
                .frame(height: ShareCardShape.notchDepth)
                .padding(.top, 28)
            main
                .padding(.top, 8)
                .frame(maxHeight: .infinity)
            Rectangle()
                .fill(theme.rule)
                .frame(height: 1)
                .padding(.top, 22)
            footer
                .padding(.top, 16)
        }
        .padding(.horizontal, Self.padding)
        .padding(.bottom, 40)
    }

    /// Providers beside the notch on the left, the period on the right.
    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: 20) {
                ForEach(card.providers, id: \.id) { provider in
                    HStack(spacing: 8) {
                        Image(provider.logoAssetName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                        Text(provider.name)
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            .foregroundStyle(theme.text)
            Spacer(minLength: 20)
            Text(card.period)
                .font(.system(size: 15))
                .foregroundStyle(theme.muted)
        }
    }

    /// The headline, then the graph and the models. With one block after
    /// the headline it floats in the middle of the room; with two, the
    /// models sit on the footer rule and the room is split between them.
    /// With nothing else the number takes the card.
    @ViewBuilder
    private var main: some View {
        let blocks = (card.hasGraph ? 1 : 0) + (card.models.isEmpty ? 0 : 1)
        if blocks == 0 {
            poster
        } else {
            VStack(spacing: 0) {
                headline
                Spacer(minLength: 20)
                if card.activity != nil || card.spend != nil {
                    graph
                    if !card.models.isEmpty {
                        Spacer(minLength: 20)
                    }
                }
                if !card.models.isEmpty {
                    models
                }
                if blocks == 1 {
                    Spacer(minLength: 20)
                }
            }
        }
    }

    private var headlineText: String {
        switch card.headline {
        case let .cost(text), let .tokens(text): text
        case .none: "No usage"
        }
    }

    /// The number with its caption under it, the stats to the right. The
    /// caption and the stat labels share a baseline.
    private var headline: some View {
        HStack(alignment: .lastTextBaseline, spacing: 40) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headlineText)
                    .font(.system(size: 96, weight: .bold))
                    .tracking(-4)
                    .foregroundStyle(theme.text)
                    .fixedSize()
                Text(card.caption)
                    .font(.system(size: 19))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 36) {
                ForEach(card.stats, id: \.label) { stat in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stat.value)
                            .font(.system(size: 30, weight: .semibold))
                            .tracking(-0.6)
                            .foregroundStyle(theme.text)
                        Text(stat.label)
                            .font(.system(size: 14))
                            .foregroundStyle(theme.muted)
                    }
                    .fixedSize()
                }
            }
        }
        .monospacedDigit()
    }

    /// The headline alone: bigger, centered vertically, stats in a row.
    private var poster: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text(headlineText)
                .font(.system(size: 168, weight: .bold))
                .tracking(-8)
                .foregroundStyle(theme.text)
                .fixedSize()
            Text(card.caption)
                .font(.system(size: 24))
                .foregroundStyle(theme.muted)
                .padding(.top, 4)
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                ForEach(card.stats, id: \.label) { stat in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stat.value)
                            .font(.system(size: 36, weight: .semibold))
                            .tracking(-0.8)
                            .foregroundStyle(theme.text)
                        Text(stat.label)
                            .font(.system(size: 15))
                            .foregroundStyle(theme.muted)
                    }
                    .frame(width: Self.contentWidth / 4, alignment: .leading)
                }
            }
            .padding(.top, 44)
            Spacer(minLength: 0)
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let graphHeight: CGFloat = 152
    private static let graphLabelSize: CGFloat = 12

    @ViewBuilder
    private var graph: some View {
        if let grid = card.activity {
            Canvas { context, size in
                ActivityHeatmap.draw(
                    grid, style: theme.graph, in: &context,
                    column: size.width / CGFloat(ActivityGrid.weeks), top: 20
                )
            }
            .frame(height: Self.graphHeight)
        } else if let series = card.spend {
            Canvas { context, size in
                let plot = CGRect(x: 0, y: 22, width: size.width, height: size.height - 22 - 24)
                SpendChart.draw(series, style: theme.graph, calendar: calendar, in: &context, plot: plot, size: size)
            }
            .overlay(alignment: .topLeading) {
                Text("Cost per day, 30 days")
                    .font(.system(size: Self.graphLabelSize))
                    .foregroundStyle(theme.muted)
            }
            .frame(height: Self.graphHeight)
        }
    }

    /// Normalized id, a bar for its share of the period's tokens, the
    /// tokens. Rows get taller when there is no graph to share the room.
    private var models: some View {
        let rowHeight: CGFloat = card.hasGraph ? 26 : 34
        return VStack(spacing: 0) {
            ForEach(card.models) { model in
                HStack(spacing: 24) {
                    Text(model.name)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 250, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.bar)
                            Capsule().fill(theme.barFill)
                                .frame(width: max(12, proxy.size.width * model.share))
                        }
                    }
                    .frame(height: 12)
                    Text(model.tokens)
                        .font(.system(size: 15))
                        .foregroundStyle(theme.muted)
                        .frame(width: 80, alignment: .trailing)
                }
                .frame(height: rowHeight)
            }
        }
        .monospacedDigit()
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 30, height: 30)
            Text("Notchlet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.text)
            Text("notchlet.com")
                .font(.system(size: 15))
                .foregroundStyle(theme.muted)
            Spacer(minLength: 20)
            Text(card.footer)
                .font(.system(size: 14))
                .foregroundStyle(theme.faint)
                .lineLimit(1)
        }
        .frame(height: 30)
    }
}

/// A rounded rectangle with the notch taken out of its top edge, the way
/// the panel hangs from the real one. The fillets where the notch meets
/// the edge curve outward like `NotchShape`'s; its bottom corners are
/// ordinary rounded corners.
struct ShareCardShape: Shape {
    static let cornerRadius: CGFloat = 34
    static let notchWidth: CGFloat = 210
    static let notchDepth: CGFloat = 34
    static let fillet: CGFloat = 10
    static let notchRadius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let r = Self.cornerRadius
        let f = Self.fillet
        let nr = Self.notchRadius
        let depth = Self.notchDepth
        let left = rect.midX - Self.notchWidth / 2
        let right = rect.midX + Self.notchWidth / 2
        let top = rect.minY

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: top))
        path.addLine(to: CGPoint(x: left - f, y: top))
        path.addQuadCurve(to: CGPoint(x: left, y: top + f), control: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left, y: top + depth - nr))
        path.addQuadCurve(to: CGPoint(x: left + nr, y: top + depth), control: CGPoint(x: left, y: top + depth))
        path.addLine(to: CGPoint(x: right - nr, y: top + depth))
        path.addQuadCurve(to: CGPoint(x: right, y: top + depth - nr), control: CGPoint(x: right, y: top + depth))
        path.addLine(to: CGPoint(x: right, y: top + f))
        path.addQuadCurve(to: CGPoint(x: right + f, y: top), control: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: top))
        path.addRelativeArc(
            center: CGPoint(x: rect.maxX - r, y: top + r),
            radius: r,
            startAngle: .degrees(-90),
            delta: .degrees(90)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addRelativeArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r,
            startAngle: .zero,
            delta: .degrees(90)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addRelativeArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(90),
            delta: .degrees(90)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: top + r))
        path.addRelativeArc(
            center: CGPoint(x: rect.minX + r, y: top + r),
            radius: r,
            startAngle: .degrees(180),
            delta: .degrees(90)
        )
        path.closeSubpath()
        return path
    }
}

/// The glass: a gradient fill under a soft shadow, a wide inner stroke for
/// the refracted edge, a color bounce at the bottom, a sheen from the top
/// left, and a thin rim lit from above.
private struct ShareGlass: View {
    let theme: ShareTheme

    var body: some View {
        let shape = ShareCardShape()
        ZStack {
            shape
                .fill(LinearGradient(gradient: Gradient(stops: theme.glassFill), startPoint: .top, endPoint: .bottom))
                .shadow(color: theme.shadow, radius: 22, y: 26)
            ZStack {
                shape.stroke(
                    LinearGradient(gradient: Gradient(stops: theme.inner), startPoint: .top, endPoint: .bottom),
                    lineWidth: theme.innerWidth
                )
                shape.fill(RadialGradient(
                    colors: [theme.bounce, theme.bounce.opacity(0)],
                    center: UnitPoint(x: 0.5, y: 1.1),
                    startRadius: 0,
                    endRadius: ShareCardView.size.width * 0.45
                ))
                shape.fill(LinearGradient(
                    colors: [.white.opacity(theme.sheen), .white.opacity(0)],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.3, y: 0.55)
                ))
            }
            .clipShape(shape)
            shape.stroke(
                LinearGradient(
                    gradient: Gradient(stops: theme.rim),
                    startPoint: UnitPoint(x: 0.2, y: 0),
                    endPoint: UnitPoint(x: 0.8, y: 1)
                ),
                lineWidth: theme.rimWidth
            )
        }
    }
}

/// One look for the card: the background, the glass and the colors the
/// content and the graphs use. Three exist; the editor shows them as
/// swatches.
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
