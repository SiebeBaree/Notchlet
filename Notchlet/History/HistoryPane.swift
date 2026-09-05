import SwiftUI

/// The history pane: how much was used rather than how much is left. Scope
/// chips when more than one provider has history, cost and tokens for
/// today, the week and the month, the activity or spend graph, then the
/// models of the selected range. Same card width as the other panes; the
/// graph fills it.
struct HistoryPane: View {
    enum Graph: String {
        case activity
        case spend
    }

    let history: UsageHistory
    @Binding var scope: UsageHistory.Scope

    @AppStorage("historyGraph") private var graph: Graph = .activity
    @State private var range: UsageHistory.Range = .month
    @State private var showsAllModels = false

    var body: some View {
        let providers = history.providersWithHistory
        let calendar = history.calendar
        let today = history.today
        let ledger = history.ledger(scope)
        let coverageStart = history.coverageStart(scope)
        let grid = ActivityGrid(
            today: today, calendar: calendar,
            tokens: ledger.byDay(today.advanced(by: -(ActivityGrid.weeks * 7), calendar: calendar) ... today)
                .mapValues(\.summary.tokens),
            coverageStart: coverageStart
        )
        let selected = ledger.summary(range.span(endingOn: today, calendar: calendar))

        VStack(alignment: .leading, spacing: 12) {
            if providers.count > 1 {
                ScopeChips(providers: providers, scope: $scope)
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach([UsageHistory.Range.today, .week, .month], id: \.self) { range in
                    RangeTile(
                        range: range,
                        summary: ledger.summary(range.span(endingOn: today, calendar: calendar)),
                        isSelected: range == self.range
                    ) {
                        self.range = range
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            NotchRule()
            graphSection(ledger: ledger, grid: grid, today: today, calendar: calendar, coverageStart: coverageStart)
            NotchRule()
            ModelTable(
                models: ledger.models(range.span(endingOn: today, calendar: calendar)),
                showsProvider: scope == .all && providers.count > 1,
                providers: providers,
                showsAll: $showsAllModels
            )
            footer(
                unpricedModels: selected.unpricedModels,
                coverageStart: coverageStart,
                graphStart: grid.start,
                providers: providers
            )
        }
    }

    @ViewBuilder
    private func graphSection(
        ledger: UsageLedger,
        grid: ActivityGrid,
        today: DayKey,
        calendar: Calendar,
        coverageStart: DayKey?
    ) -> some View {
        HStack(spacing: 10) {
            HoverTextButton("Activity", isActive: graph == .activity) { setGraph(.activity) }
            HoverTextButton("Spend", isActive: graph == .spend) { setGraph(.spend) }
            Spacer()
            Text(graph == .activity ? "Tokens, 12 months" : "Cost per day, 30 days")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
        switch graph {
        case .activity:
            ActivityHeatmap(grid: grid, days: ledger.byDay(grid.start ... today), calendar: calendar)
                .zIndex(1)
        case .spend:
            let span = today.advanced(by: 1 - SpendSeries.days, calendar: calendar) ... today
            let days = ledger.byDay(span)
            SpendChart(
                series: SpendSeries(
                    today: today, calendar: calendar,
                    costs: days.compactMapValues(\.summary.cost),
                    coverageStart: coverageStart
                ),
                days: days,
                calendar: calendar
            )
            .zIndex(1)
        }
    }

    private func setGraph(_ graph: Graph) {
        guard graph != self.graph else { return }
        self.graph = graph
        Analytics.capture(.settingChanged(key: "history_graph", value: graph.rawValue))
    }

    /// The pricing caveat, unpriced models and the archive's age, or what
    /// is standing in the way of any numbers at all.
    private func footer(
        unpricedModels: [String],
        coverageStart: DayKey?,
        graphStart: DayKey,
        providers: [any UsageProvider]
    ) -> some View {
        let failed = providers.filter { history.failedProviderIDs.contains($0.id) }
        let text: String = if providers.isEmpty {
            "No usage logs found"
        } else if !failed.isEmpty {
            "Could not load \(failed.map(\.name).joined(separator: " and ")) history"
        } else if history.lastIngestAt == nil {
            "Reading logs"
        } else {
            HistoryCopy.footer(
                unpricedModels: unpricedModels, coverageStart: coverageStart,
                graphStart: graphStart, calendar: history.calendar
            )
        }
        return Text(text)
            .font(.system(size: 10))
            .foregroundStyle(failed.isEmpty ? .white.opacity(0.4) : NotchPalette.amber)
            .lineLimit(1)
    }
}

/// Cost over tokens for one range. The selected range feeds the model
/// table below. A range with nothing in it says so rather than $0.00.
private struct RangeTile: View {
    let range: UsageHistory.Range
    let summary: UsageLedger.Summary
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(isSelected ? 0.85 : 0.5))
                if summary.tokens == 0 {
                    Text("No usage")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 4)
                } else if let cost = summary.cost {
                    Text(HistoryCopy.cost(cost))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(HistoryCopy.tokens(summary.tokens)) tokens")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.55))
                } else {
                    Text(HistoryCopy.tokens(summary.tokens))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("tokens, unpriced")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var label: String {
        switch range {
        case .today: "Today"
        case .week: "7 days"
        case .month: "30 days"
        case .year: "12 months"
        }
    }
}

/// Models of the selected range, input and output apart. The first few
/// show; the rest unfold in place.
private struct ModelTable: View {
    let models: [UsageLedger.ModelUsage]
    let showsProvider: Bool
    let providers: [any UsageProvider]
    @Binding var showsAll: Bool

    private static let visible = 4
    private static let numberWidth: CGFloat = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            row(
                Text("Model").foregroundStyle(.white.opacity(0.45)),
                Text("Input").foregroundStyle(.white.opacity(0.45)),
                Text("Output").foregroundStyle(.white.opacity(0.45))
            )
            .font(.system(size: 10))
            ForEach(showsAll ? models : Array(models.prefix(Self.visible))) { model in
                row(
                    name(of: model),
                    Text(HistoryCopy.tokens(model.tokens.promptTokens)).foregroundStyle(.white.opacity(0.85)),
                    Text(HistoryCopy.tokens(model.tokens.output)).foregroundStyle(.white.opacity(0.85))
                )
                .font(.system(size: 11))
            }
            if models.count > Self.visible {
                HoverTextButton(showsAll ? "Fewer" : "\(models.count - Self.visible) more") {
                    withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                        showsAll.toggle()
                    }
                }
                .font(.system(size: 10))
            }
            if models.isEmpty {
                Text("No usage")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .monospacedDigit()
    }

    private func name(of model: UsageLedger.ModelUsage) -> Text {
        var text = Text(model.model ?? "unknown model").foregroundStyle(.white)
        if showsProvider, let provider = providers.first(where: { $0.id == model.providerID }) {
            text = text + Text("  \(provider.name)").foregroundStyle(.white.opacity(0.4)).font(.system(size: 10))
        }
        return text
    }

    private func row(_ name: Text, _ input: Text, _ output: Text) -> some View {
        HStack(spacing: 8) {
            name
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            input
                .frame(width: Self.numberWidth, alignment: .trailing)
            output
                .frame(width: Self.numberWidth, alignment: .trailing)
        }
    }
}
