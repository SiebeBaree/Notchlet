import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Turns a card into pixels and moves them out of the app. Rendering goes
/// through `ImageRenderer` at 2x, so a landscape card is 2400 by 1350.
enum ShareRenderer {
    static let scale: CGFloat = 2

    static func image(card: ShareCard, theme: ShareTheme, calendar: Calendar) -> CGImage? {
        let renderer = ImageRenderer(content: ShareCardView(card: card, theme: theme, calendar: calendar))
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.cgImage
    }

    static func png(card: ShareCard, theme: ShareTheme, calendar: Calendar) -> Data? {
        guard let image = image(card: card, theme: theme, calendar: calendar) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// PNG for apps that take it, TIFF for the ones that only take that.
    static func copy(_ png: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    /// "Notchlet usage Sep 3.png".
    static func fileName(today: DayKey, calendar: Calendar) -> String {
        "Notchlet usage \(HistoryCopy.shortDay(today, calendar: calendar)).png"
    }

    /// A save panel over the editor, starting in Downloads. Calls back only
    /// when a file was written.
    static func save(_ png: Data, fileName: String, from window: NSWindow, completion: @escaping () -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = fileName
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url, (try? png.write(to: url)) != nil else { return }
            completion()
        }
    }
}
