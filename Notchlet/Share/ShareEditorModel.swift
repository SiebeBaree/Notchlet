import AppKit
import SwiftUI

/// The options (remembered across opens), the card they produce, and what
/// Copy, Save and Share do with it.
@Observable
final class ShareEditorModel {
    private static let periodKey = "share.period"
    private static let costKey = "share.cost"
    private static let graphKey = "share.graph"
    private static let modelsKey = "share.models"
    private static let themeKey = "share.theme"
    private static let planKey = "share.plan"

    let history: UsageHistory
    /// For the plans behind the live limits.
    private let store: UsageStore
    var scope: UsageHistory.Scope
    var options: ShareOptions {
        didSet { save() }
    }

    private(set) var toast: String?
    private var toastTask: Task<Void, Never>?
    /// What the share picker pops out of.
    weak var shareAnchor: NSView?

    init(history: UsageHistory, store: UsageStore, scope: UsageHistory.Scope) {
        self.history = history
        self.store = store
        self.scope = scope
        let defaults = UserDefaults.standard
        var options = ShareOptions()
        if let period = defaults.string(forKey: Self.periodKey).flatMap(UsageHistory.Range.init(rawValue:)) {
            options.period = period
        }
        if defaults.object(forKey: Self.costKey) != nil {
            options.showsCost = defaults.bool(forKey: Self.costKey)
        }
        if let graph = defaults.string(forKey: Self.graphKey).flatMap(ShareGraph.init(rawValue:)) {
            options.graph = graph
        }
        if defaults.object(forKey: Self.modelsKey) != nil {
            options.showsModels = defaults.bool(forKey: Self.modelsKey)
        }
        if let theme = defaults.string(forKey: Self.themeKey).flatMap(ShareThemeID.init(rawValue:)) {
            options.theme = theme
        }
        if defaults.object(forKey: Self.planKey) != nil {
            options.showsPlan = defaults.bool(forKey: Self.planKey)
        }
        self.options = options
    }

    /// The plans behind the providers on the image, in scope order.
    /// Nil for a provider that has not reported one.
    var plans: [(provider: ShareCard.Provider, plan: UsagePlan?)] {
        scopedProviders.map { provider in
            (provider, store.entries.first { $0.id == provider.id }?.snapshot?.plan)
        }
    }

    /// Every provider on the image needs a priced plan for the sum to mean
    /// anything.
    var planPrice: Double? {
        let prices = plans.compactMap(\.plan?.monthlyPrice)
        guard prices.count == plans.count, !prices.isEmpty else { return nil }
        return prices.reduce(0, +)
    }

    /// What the plan row says under its title: the plans and the price, or
    /// what is missing.
    var planDetail: String {
        guard options.period == .month, options.showsCost, summary.cost != nil, !isReadingLogs, summary.tokens > 0
        else { return "Needs 30 days with cost on" }
        if let planPrice {
            let names = plans.compactMap(\.plan?.name)
            return "\(names.joined(separator: " and ")), \(ShareCard.planLabel(planPrice)) a month"
        }
        if let missing = plans.first(where: { $0.plan == nil }) {
            return "\(missing.provider.name) has not said which plan"
        }
        if let unpriced = plans.first(where: { $0.plan?.monthlyPrice == nil })?.plan {
            return "No list price for \(unpriced.name)"
        }
        return "No plan found"
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(options.period.rawValue, forKey: Self.periodKey)
        defaults.set(options.showsCost, forKey: Self.costKey)
        defaults.set(options.graph.rawValue, forKey: Self.graphKey)
        defaults.set(options.showsModels, forKey: Self.modelsKey)
        defaults.set(options.showsPlan, forKey: Self.planKey)
        defaults.set(options.theme.rawValue, forKey: Self.themeKey)
    }

    var providers: [any UsageProvider] {
        history.providersWithHistory
    }

    /// All when the chosen provider no longer has history. Labels and data
    /// both go through this so they never disagree.
    var effectiveScope: UsageHistory.Scope {
        if case let .provider(id) = scope, !providers.contains(where: { $0.id == id }) {
            return .all
        }
        return scope
    }

    var scopedProviders: [ShareCard.Provider] {
        let all = providers
        let chosen: [any UsageProvider] = if case let .provider(id) = effectiveScope {
            all.filter { $0.id == id }
        } else {
            all
        }
        return chosen.map { ShareCard.Provider(id: $0.id, name: $0.name, logoAssetName: $0.logoAssetName) }
    }

    /// Today and yesterday only arrive with the first read of the logs.
    var isReadingLogs: Bool {
        history.lastIngestAt == nil
    }

    var theme: ShareTheme {
        ShareTheme.theme(options.theme)
    }

    var summary: UsageLedger.Summary {
        history.summary(options.period, scope: effectiveScope)
    }

    var card: ShareCard {
        ShareCard.make(
            options: options,
            providers: scopedProviders,
            ledger: history.ledger(effectiveScope),
            coverageStart: history.coverageStart(effectiveScope),
            planPrice: planPrice,
            today: history.today,
            calendar: history.calendar
        )
    }

    var canExport: Bool {
        !isReadingLogs && card.hasUsage
    }

    private func image() -> CGImage? {
        ShareRenderer.image(card: card, theme: theme, calendar: history.calendar)
    }

    private func png() -> Data? {
        image().flatMap(ShareRenderer.png)
    }

    func copy() {
        guard canExport, let image = image() else { return }
        ShareRenderer.copy(image)
        show(toast: "Copied. Paste it anywhere.")
        track("copy")
    }

    func save(from window: NSWindow) {
        guard canExport, let png = png() else { return }
        let name = ShareRenderer.fileName(today: history.today, calendar: history.calendar)
        ShareRenderer.save(png, fileName: name, from: window) { [weak self] in
            self?.show(toast: "Saved to Downloads.")
            self?.track("save")
        }
    }

    func share() {
        guard canExport, let anchor = shareAnchor, let image = image() else { return }
        let picker = NSSharingServicePicker(items: [NSImage(cgImage: image, size: ShareCardView.size)])
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        track("share")
    }

    private func show(toast: String) {
        self.toast = toast
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                self?.toast = nil
            }
        }
    }

    private func track(_ method: String) {
        Analytics.capture(.shareExported(
            method: method,
            theme: options.theme.rawValue,
            period: options.period.rawValue,
            graph: options.graph.rawValue,
            cost: options.showsCost,
            models: options.showsModels
        ))
    }
}
