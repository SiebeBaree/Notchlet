import SwiftUI

/// One blue, dark to bright, on the black card. Blue stays clear of the
/// green, yellow and red the rings use for pace. Unknown days get a warmer
/// dark gray that is neither empty nor a level, so the edge of coverage
/// reads without a legend entry.
enum ActivityPalette {
    static let levels = [
        Color(red: 0.07, green: 0.25, blue: 0.48),
        Color(red: 0.12, green: 0.37, blue: 0.68),
        Color(red: 0.22, green: 0.53, blue: 0.90),
        Color(red: 0.53, green: 0.71, blue: 0.94),
    ]
    static let empty = Color.white.opacity(0.06)
    static let unknown = Color(red: 0.16, green: 0.14, blue: 0.12)
    static let line = levels[2]
}

/// The colors and label size one drawing of a graph uses: the pane's, or a
/// share card theme's. `unknown` is the fill for days before coverage; nil
/// leaves them out.
struct GraphStyle {
    var levels: [Color]
    var empty: Color
    var unknown: Color?
    var line: Color
    var text: Color
    var rule: Color
    var labelSize: CGFloat

    static let pane = GraphStyle(
        levels: ActivityPalette.levels,
        empty: ActivityPalette.empty,
        unknown: ActivityPalette.unknown,
        line: ActivityPalette.line,
        text: .white.opacity(0.45),
        rule: .white.opacity(0.15),
        labelSize: 8
    )

    func color(for fill: ActivityGrid.Fill) -> Color? {
        switch fill {
        case .unknown: unknown
        case .empty: empty
        case let .level(level): levels[min(max(level, 1), levels.count) - 1]
        }
    }
}

/// Both graphs share one height for a given width, so switching between
/// them never moves the rows below. Measured in columns of the heatmap:
/// 53 columns wide, 7 rows plus a strip of 1.6 columns for month labels.
enum GraphLayout {
    static let labelStripColumns: CGFloat = 1.6
    static let aspectRatio = CGFloat(ActivityGrid.weeks) / (CGFloat(ActivityGrid.rows) + labelStripColumns)
    static let tooltipWidth: CGFloat = 156

    /// Where a tooltip for a mark at `x` goes so it stays inside the graph.
    static func tooltipX(for x: CGFloat, width: CGFloat) -> CGFloat {
        min(max(x - tooltipWidth / 2, 0), max(width - tooltipWidth, 0))
    }
}

/// Twelve months of tokens as a grid of days. One `Canvas` and one hover
/// handler: 371 cells as views would each hit-test on every cursor move,
/// which is the CPU cost the collapsed notch was built to avoid.
struct ActivityHeatmap: View {
    let grid: ActivityGrid
    let days: [DayKey: UsageLedger.DayUsage]
    let calendar: Calendar

    @State private var hovered: ActivityGrid.Cell?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let column = size.width / CGFloat(ActivityGrid.weeks)
            let top = column * GraphLayout.labelStripColumns
            Canvas { context, _ in
                Self.draw(grid, style: .pane, in: &context, column: column, top: top)
                if let hovered {
                    let gap = column * 0.22
                    let rect = Self.rect(of: hovered, column: column, top: top, gap: gap).insetBy(dx: -1, dy: -1)
                    context.stroke(
                        Path(roundedRect: rect, cornerRadius: 2),
                        with: .color(.white.opacity(0.85)),
                        lineWidth: 1
                    )
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case let .active(point):
                    let cell = grid.cell(atColumn: Int(point.x / column), row: Int((point.y - top) / column))
                    if cell != hovered {
                        hovered = point.y >= top ? cell : nil
                    }
                case .ended:
                    hovered = nil
                }
            }
            .overlay(alignment: .topLeading) {
                if let hovered {
                    let rect = Self.rect(of: hovered, column: column, top: top, gap: 0)
                    DayTooltip(
                        day: hovered.day,
                        usage: days[hovered.day],
                        isUnknown: hovered.fill == .unknown,
                        calendar: calendar
                    )
                    .offset(x: GraphLayout.tooltipX(for: rect.midX, width: size.width), y: rect.maxY + 4)
                }
            }
        }
        .aspectRatio(GraphLayout.aspectRatio, contentMode: .fit)
    }

    /// Month labels along the top, then one rounded square per day. Shared
    /// with the share card, which draws the same grid at its own size.
    static func draw(
        _ grid: ActivityGrid,
        style: GraphStyle,
        in context: inout GraphicsContext,
        column: CGFloat,
        top: CGFloat
    ) {
        let gap = column * 0.22
        let radius = max(1.5, column * 0.16)
        for label in grid.monthLabels {
            let text = Text(label.text).font(.system(size: style.labelSize)).foregroundStyle(style.text)
            context.draw(text, at: CGPoint(x: CGFloat(label.column) * column, y: 0), anchor: .topLeading)
        }
        for cell in grid.cells {
            guard let color = style.color(for: cell.fill) else { continue }
            let rect = rect(of: cell, column: column, top: top, gap: gap)
            context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color))
        }
    }

    private static func rect(of cell: ActivityGrid.Cell, column: CGFloat, top: CGFloat, gap: CGFloat) -> CGRect {
        CGRect(
            x: CGFloat(cell.column) * column + gap / 2,
            y: top + CGFloat(cell.row) * column + gap / 2,
            width: column - gap,
            height: column - gap
        )
    }
}

/// Thirty days of dollars as a line, the way CodexBar's cost history
/// reads. The line breaks over days before coverage started rather than
/// drawing them as zero.
struct SpendChart: View {
    let series: SpendSeries
    let days: [DayKey: UsageLedger.DayUsage]
    let calendar: Calendar

    @State private var hoveredIndex: Int?

    private static let axisHeight: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let plot = CGRect(x: 0, y: 4, width: size.width, height: size.height - 4 - Self.axisHeight)
            Canvas { context, _ in
                Self.draw(series, style: .pane, calendar: calendar, in: &context, plot: plot, size: size)
                if let hoveredIndex, let cost = series.points[hoveredIndex].cost {
                    let at = CGPoint(x: Self.x(hoveredIndex, in: plot), y: y(cost, in: plot))
                    var hairline = Path()
                    hairline.move(to: CGPoint(x: at.x, y: plot.minY))
                    hairline.addLine(to: CGPoint(x: at.x, y: plot.maxY))
                    context.stroke(hairline, with: .color(.white.opacity(0.25)), lineWidth: 1)
                    context.fill(
                        Path(ellipseIn: CGRect(x: at.x - 3, y: at.y - 3, width: 6, height: 6)),
                        with: .color(.white)
                    )
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case let .active(point):
                    let count = series.points.count
                    let index = min(max(Int((point.x / size.width * CGFloat(count - 1)).rounded()), 0), count - 1)
                    if index != hoveredIndex {
                        hoveredIndex = index
                    }
                case .ended:
                    hoveredIndex = nil
                }
            }
            .overlay(alignment: .topLeading) {
                if let hoveredIndex {
                    let point = series.points[hoveredIndex]
                    DayTooltip(day: point.day, usage: days[point.day], isUnknown: point.cost == nil, calendar: calendar)
                        .offset(
                            x: GraphLayout.tooltipX(for: Self.x(hoveredIndex, in: plot), width: size.width),
                            y: plot.maxY + 2
                        )
                }
            }
        }
        .aspectRatio(GraphLayout.aspectRatio, contentMode: .fit)
    }

    /// The area, the line, the baseline, the peak at the top right and the
    /// first and last day under the plot. Shared with the share card.
    static func draw(
        _ series: SpendSeries,
        style: GraphStyle,
        calendar: Calendar,
        in context: inout GraphicsContext,
        plot: CGRect,
        size: CGSize
    ) {
        var baseline = Path()
        baseline.move(to: CGPoint(x: plot.minX, y: plot.maxY))
        baseline.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
        context.stroke(baseline, with: .color(style.rule), lineWidth: 1)

        var line = Path()
        var area = Path()
        var open = false
        for (index, point) in series.points.enumerated() {
            guard let cost = point.cost else {
                if open {
                    area.addLine(to: CGPoint(x: x(index, in: plot), y: plot.maxY))
                    area.closeSubpath()
                }
                open = false
                continue
            }
            let at = CGPoint(x: x(index, in: plot), y: y(cost, in: plot, max: series.maxCost))
            if open {
                line.addLine(to: at)
                area.addLine(to: at)
            } else {
                line.move(to: at)
                area.move(to: CGPoint(x: at.x, y: plot.maxY))
                area.addLine(to: at)
                open = true
            }
        }
        if open, let last = series.points.indices.last {
            area.addLine(to: CGPoint(x: x(last, in: plot), y: plot.maxY))
            area.closeSubpath()
        }
        context.fill(area, with: .color(style.line.opacity(0.18)))
        context.stroke(
            line,
            with: .color(style.line),
            style: StrokeStyle(lineWidth: max(1.5, size.width / 400), lineJoin: .round)
        )

        let font = Font.system(size: style.labelSize)
        if series.maxCost > 0 {
            let top = Text(HistoryCopy.cost(series.maxCost)).font(font).foregroundStyle(style.text)
            context.draw(top, at: CGPoint(x: plot.maxX, y: 0), anchor: .topTrailing)
        }
        if let first = series.points.first, let last = series.points.last {
            context.draw(
                Text(HistoryCopy.shortDay(first.day, calendar: calendar)).font(font).foregroundStyle(style.text),
                at: CGPoint(x: plot.minX, y: size.height),
                anchor: .bottomLeading
            )
            context.draw(
                Text(HistoryCopy.shortDay(last.day, calendar: calendar)).font(font).foregroundStyle(style.text),
                at: CGPoint(x: plot.maxX, y: size.height),
                anchor: .bottomTrailing
            )
        }
    }

    private static func x(_ index: Int, in plot: CGRect) -> CGFloat {
        plot.minX + plot.width * CGFloat(index) / CGFloat(max(SpendSeries.days - 1, 1))
    }

    private func y(_ cost: Double, in plot: CGRect) -> CGFloat {
        Self.y(cost, in: plot, max: series.maxCost)
    }

    private static func y(_ cost: Double, in plot: CGRect, max: Double) -> CGFloat {
        guard max > 0 else { return plot.maxY }
        return plot.maxY - plot.height * CGFloat(cost / max)
    }
}

/// What a day held: the total, then its models. Shared by both graphs.
struct DayTooltip: View {
    let day: DayKey
    let usage: UsageLedger.DayUsage?
    let isUnknown: Bool
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(HistoryCopy.dayTitle(day, calendar: calendar))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
            if isUnknown {
                Text("Before Notchlet started reading logs")
                    .foregroundStyle(.white.opacity(0.55))
            } else if let usage, usage.summary.tokens > 0 {
                Text(Self.totalLine(usage.summary))
                    .foregroundStyle(.white.opacity(0.85))
                ForEach(usage.models.prefix(3)) { model in
                    HStack(spacing: 8) {
                        Text(model.model ?? "unknown model")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Text(HistoryCopy.tokens(model.tokens.total))
                    }
                    .foregroundStyle(.white.opacity(0.55))
                }
                if usage.models.count > 3 {
                    Text("\(usage.models.count - 3) more")
                        .foregroundStyle(.white.opacity(0.4))
                }
            } else {
                Text("No usage")
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .font(.system(size: 10))
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(width: GraphLayout.tooltipWidth, alignment: .leading)
        .background(Color(white: 0.11), in: .rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.15), lineWidth: 1))
        .allowsHitTesting(false)
    }

    private static func totalLine(_ summary: UsageLedger.Summary) -> String {
        var line = "\(HistoryCopy.tokens(summary.tokens)) tokens"
        if let cost = summary.cost {
            line += " · \(HistoryCopy.cost(cost))"
        }
        return line
    }
}
