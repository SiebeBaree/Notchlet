import AppKit
import SwiftUI

/// The share editor's state and actions: the options (remembered across
/// opens), the card they produce from the history store, and what Copy,
/// Save and Share do with it. Owned by the window controller and shown by
/// `ShareEditorView`.
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

    /// A line over the preview, cleared after a moment.
    private(set) var toast: String?
    private var toastTask: Task<Void, Never>?
    /// The view the share picker pops out of.
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

    /// The scope the card and the chips use: the chosen one, or all when
    /// its provider no longer has history (switched off while the window
    /// was open, say). Labels and data both go through this so they never
    /// disagree.
    var effectiveScope: UsageHistory.Scope {
        if case let .provider(id) = scope, !providers.contains(where: { $0.id == id }) {
            return .all
        }
        return scope
    }

    /// The providers the card names.
    var scopedProviders: [ShareCard.Provider] {
        let all = providers
        let chosen: [any UsageProvider] = if case let .provider(id) = effectiveScope {
            all.filter { $0.id == id }
        } else {
            all
        }
        return chosen.map { ShareCard.Provider(id: $0.id, name: $0.name, logoAssetName: $0.logoAssetName) }
    }

    /// The archives show right away at launch, but today and yesterday
    /// only arrive with the first read of the logs.
    var isReadingLogs: Bool {
        history.lastIngestAt == nil
    }

    var theme: ShareTheme {
        ShareTheme.theme(options.theme)
    }

    /// What the period holds, for the editor's disabled states.
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

/// One window, reused across opens. The app has no menu bar, so the
/// window handles its own key equivalents.
final class ShareEditorWindowController: NSWindowController {
    static let windowSize = CGSize(width: 980, height: 640)

    private let history: UsageHistory
    private var model: ShareEditorModel?

    init(history: UsageHistory) {
        self.history = history
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Opens the editor scoped like the pane it came from, or rescopes the
    /// open one, and brings it to the front. Activating the app is needed
    /// because the notch panel never does.
    func show(scope: UsageHistory.Scope) {
        if let model, let window {
            model.scope = scope
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = ShareEditorModel(history: history, scope: scope)
        self.model = model
        let window = ShareEditorWindow(
            contentRect: CGRect(origin: .zero, size: Self.windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Share usage"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(white: 0.11, alpha: 1)
        window.isReleasedWhenClosed = false
        window.onCopy = { [weak model] in model?.copy() }
        window.onSave = { [weak model, weak window] in
            guard let window else { return }
            model?.save(from: window)
        }
        let hosting = NSHostingView(rootView: ShareEditorView(model: model))
        hosting.sizingOptions = []
        window.contentView = hosting
        self.window = window
        center(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Centered on the notch's screen rather than wherever the cursor is.
    private func center(_ window: NSWindow) {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
        else { return }
        let frame = screen.visibleFrame
        window.setFrameOrigin(CGPoint(
            x: (frame.midX - Self.windowSize.width / 2).rounded(),
            y: (frame.midY - Self.windowSize.height / 2).rounded()
        ))
    }
}

/// Cmd+C, Cmd+S, Cmd+W and Escape, without a main menu to route them.
private final class ShareEditorWindow: NSWindow {
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers {
        case "c":
            onCopy?()
        case "s":
            onSave?()
        case "w":
            close()
        default:
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// The preview on the left, the inspector on the right: what the numbers
/// cover, what the card includes, how it looks, then the export buttons.
struct ShareEditorView: View {
    @Bindable var model: ShareEditorModel

    private static let inspectorWidth: CGFloat = 290

    var body: some View {
        HStack(spacing: 0) {
            preview
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)
            inspector
                .frame(width: Self.inspectorWidth)
        }
        .frame(
            width: ShareEditorWindowController.windowSize.width,
            height: ShareEditorWindowController.windowSize.height
        )
        .background(Color(white: 0.11))
    }

    /// The card at whatever scale fits, on a dotted field so its edges and
    /// shadow read.
    private var preview: some View {
        GeometryReader { proxy in
            let scale = min(
                (proxy.size.width - 56) / ShareCardView.size.width,
                (proxy.size.height - 56) / ShareCardView.size.height
            )
            ZStack {
                DottedField()
                ShareCardView(card: model.card, theme: model.theme, calendar: model.history.calendar)
                    .scaleEffect(scale)
                    .frame(width: ShareCardView.size.width * scale, height: ShareCardView.size.height * scale)
                    .clipShape(.rect(cornerRadius: 12 * scale))
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 20)
                    .animation(.spring(duration: 0.25, bounce: 0.1), value: model.options)
                if let toast = model.toast {
                    Text(toast)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color(white: 0.16), in: .capsule)
                        .overlay(Capsule().stroke(.white.opacity(0.14)))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 18)
                        .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                group("Show") {
                    if model.providers.count > 1 {
                        ScopeChips(providers: model.providers, scope: Binding(
                            get: { model.effectiveScope },
                            set: { model.scope = $0 }
                        ), size: 11.5)
                    }
                    Picker("Period", selection: $model.options.period) {
                        Text("Today").tag(UsageHistory.Range.today)
                        Text("7 days").tag(UsageHistory.Range.week)
                        Text("30 days").tag(UsageHistory.Range.month)
                        Text("12 months").tag(UsageHistory.Range.year)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                }
                group("Include") {
                    includeRows
                }
                group("Look") {
                    HStack(spacing: 10) {
                        ForEach(ShareThemeID.allCases, id: \.self) { id in
                            ThemeSwatch(theme: ShareTheme.theme(id), isSelected: model.options.theme == id) {
                                model.options.theme = id
                            }
                        }
                        Spacer()
                        Text(model.theme.name)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(16)
            Spacer(minLength: 0)
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
            HStack(spacing: 8) {
                Spacer()
                Button("Save…") {
                    if let window = NSApp.keyWindow {
                        model.save(from: window)
                    }
                }
                Button("Share…") {
                    model.share()
                }
                .background(PickerAnchor(model: model))
                Button("Copy image") {
                    model.copy()
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.regular)
            .disabled(!model.canExport)
            .padding(12)
        }
    }

    /// Each row says what it adds, or why it cannot right now.
    @ViewBuilder
    private var includeRows: some View {
        let summary = model.summary
        let hasUsage = !model.isReadingLogs && summary.tokens > 0
        let noUsage = model.isReadingLogs ? "Reading logs" : "No usage in this period"
        includeRow(
            "Cost",
            detail: !hasUsage ? noUsage : summary
                .cost == nil ? "Nothing priced in this period" : "Tokens become the headline when off",
            isOn: $model.options.showsCost,
            isAvailable: hasUsage && summary.cost != nil
        )
        VStack(alignment: .leading, spacing: 6) {
            Picker("Graph", selection: $model.options.graph) {
                Text("Activity").tag(ShareGraph.activity)
                Text("Spend").tag(ShareGraph.spend)
                Text("None").tag(ShareGraph.none)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            Text(graphDetail)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.vertical, 4)
        includeRow(
            "Models",
            detail: hasUsage ? "Top \(ShareCard.modelRowCount(graph: model.options.graph)), with share bars" : noUsage,
            isOn: $model.options.showsModels,
            isAvailable: hasUsage
        )
    }

    private var graphDetail: String {
        switch model.options.graph {
        case .activity: "12 months of tokens per day"
        case .spend: "Cost per day, 30 days"
        case .none: "Just the numbers"
        }
    }

    private func includeRow(_ title: String, detail: String, isOn: Binding<Bool>, isAvailable: Bool) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(isAvailable ? 0.9 : 0.4))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!isAvailable)
        }
        .padding(.vertical, 4)
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 10)
            content()
        }
    }
}

private struct ThemeSwatch: View {
    let theme: ShareTheme
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Circle()
                .fill(LinearGradient(colors: theme.swatch, startPoint: .top, endPoint: .bottom))
                .frame(width: 24, height: 24)
                .overlay(Circle().stroke(.white, lineWidth: isSelected ? 2 : 0).padding(-3))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(theme.name)
    }
}

/// A dotted dark field behind the preview.
private struct DottedField: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 18
            var x: CGFloat = step / 2
            while x < size.width {
                var y: CGFloat = step / 2
                while y < size.height {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                        with: .color(.white.opacity(0.07))
                    )
                    y += step
                }
                x += step
            }
        }
        .background(Color(white: 0.08))
    }
}

/// An empty view the share picker can anchor to, behind the Share button.
private struct PickerAnchor: NSViewRepresentable {
    let model: ShareEditorModel

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        model.shareAnchor = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
