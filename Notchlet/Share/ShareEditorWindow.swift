import AppKit
import SwiftUI

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
