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

    let history: UsageHistory
    var scope: UsageHistory.Scope
    var options: ShareOptions {
        didSet { save() }
    }

    private(set) var toast: String?
    private var toastTask: Task<Void, Never>?
    /// What the share picker pops out of.
    weak var shareAnchor: NSView?

    init(history: UsageHistory, scope: UsageHistory.Scope) {
        self.history = history
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
        self.options = options
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(options.period.rawValue, forKey: Self.periodKey)
        defaults.set(options.showsCost, forKey: Self.costKey)
        defaults.set(options.graph.rawValue, forKey: Self.graphKey)
        defaults.set(options.showsModels, forKey: Self.modelsKey)
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
            today: history.today,
            calendar: history.calendar
        )
    }

    var canExport: Bool {
        !isReadingLogs && card.hasUsage
    }

    private func png() -> Data? {
        ShareRenderer.png(card: card, theme: theme, calendar: history.calendar)
    }

    func copy() {
        guard canExport, let png = png() else { return }
        ShareRenderer.copy(png)
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
        guard canExport, let anchor = shareAnchor, let png = png(), let image = NSImage(data: png) else { return }
        let picker = NSSharingServicePicker(items: [image])
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
