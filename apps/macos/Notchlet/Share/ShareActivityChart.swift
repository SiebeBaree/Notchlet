import SwiftUI

struct ShareActivityChart: View {
    let series: ShareActivitySeries
    let style: GraphStyle
    let calendar: Calendar

    var body: some View {
        Canvas { context, size in
            let plot = CGRect(x: 0, y: 22, width: size.width, height: size.height - 46)
            let column = plot.width / CGFloat(max(series.points.count, 1))
            let width = column * 0.8
            for (index, point) in series.points.enumerated() {
                let fraction = series.maxTokens > 0 ? Double(point.tokens) / Double(series.maxTokens) : 0
                // Quiet days remain visible; the tallest bar sets the scale.
                let height = max(3, plot.height * fraction)
                let rect = CGRect(
                    x: plot.minX + (CGFloat(index) + 0.5) * column - width / 2,
                    y: plot.maxY - height, width: width, height: height
                )
                let color = point.level == 0 ? style.empty : style.levels[point.level - 1]
                context.fill(Path(roundedRect: rect, cornerRadius: min(3, width / 2)), with: .color(color))
            }

            let font = Font.system(size: style.labelSize)
            context.draw(
                Text(series.weekly ? "Tokens per week" : "Tokens per day").font(font).foregroundStyle(style.text),
                at: .zero, anchor: .topLeading
            )
            if series.maxTokens > 0 {
                context.draw(
                    Text(HistoryCopy.tokens(series.maxTokens)).font(font).foregroundStyle(style.text),
                    at: CGPoint(x: size.width, y: 0), anchor: .topTrailing
                )
            }
            if !series.weekly, series.points.count <= 7 {
                var labelCalendar = calendar
                labelCalendar.locale = Locale(identifier: "en_US")
                for (index, point) in series.points.enumerated() {
                    let weekday = calendar.component(.weekday, from: point.day.start(in: calendar))
                    context.draw(
                        Text(labelCalendar.shortWeekdaySymbols[weekday - 1]).font(font).foregroundStyle(style.text),
                        at: CGPoint(x: (CGFloat(index) + 0.5) * column, y: size.height), anchor: .bottom
                    )
                }
            } else if let first = series.points.first {
                context.draw(
                    Text(HistoryCopy.shortDay(first.day, calendar: calendar)).font(font).foregroundStyle(style.text),
                    at: CGPoint(x: 0, y: size.height), anchor: .bottomLeading
                )
                context.draw(
                    Text(HistoryCopy.shortDay(series.end, calendar: calendar)).font(font).foregroundStyle(style.text),
                    at: CGPoint(x: size.width, y: size.height), anchor: .bottomTrailing
                )
                let middle = series.points.count / 2
                context.draw(
                    Text(HistoryCopy.shortDay(series.points[middle].day, calendar: calendar))
                        .font(font).foregroundStyle(style.text),
                    at: CGPoint(x: (CGFloat(middle) + 0.5) * column, y: size.height), anchor: .bottom
                )
            }
        }
    }
}
