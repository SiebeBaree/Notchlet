import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// `ImageRenderer` at 2x, so a card is 2400 by 1350 pixels.
enum ShareRenderer {
    static let scale: CGFloat = 2

    /// Drawn into an 8-bit RGB bitmap of our own: `cgImage` hands back 16
    /// bits per channel with alpha, which made a 10 MB PNG that took a
    /// second to encode.
    static func image(card: ShareCard, theme: ShareTheme, calendar: Calendar) -> CGImage? {
        let renderer = ImageRenderer(content: ShareCardView(card: card, theme: theme, calendar: calendar))
        renderer.isOpaque = true
        var image: CGImage?
        renderer.render(rasterizationScale: scale) { size, draw in
            guard let context = CGContext(
                data: nil,
                width: Int(size.width * scale),
                height: Int(size.height * scale),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return }
            context.scaleBy(x: scale, y: scale)
            draw(context)
            image = context.makeImage()
        }
        return image
    }

    static func png(card: ShareCard, theme: ShareTheme, calendar: Calendar) -> Data? {
        image(card: card, theme: theme, calendar: calendar).flatMap(png)
    }

    static func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// PNG for apps that take it, TIFF for the ones that only take that,
    /// both from the same bitmap.
    static func copy(_ image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let bitmap = NSBitmapImageRep(cgImage: image)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = bitmap.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    /// "Notchlet usage Sep 3.png".
    static func fileName(today: DayKey, calendar: Calendar) -> String {
        "Notchlet usage \(HistoryCopy.shortDay(today, calendar: calendar)).png"
    }

    /// Calls back only when a file was written.
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
