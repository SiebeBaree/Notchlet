import AppKit
import SwiftUI

/// A `CAShapeLayer` along `NotchShape.waitLine` with a Core Animation
/// opacity animation: the window server runs it, so the app draws nothing
/// per frame.
struct WaitOutline: NSViewRepresentable {
    var color: NSColor
    var topRadius: CGFloat
    /// The black shape's; the line's own is concentric.
    var bottomRadius: CGFloat
    /// From the shape's edge to the stroke's centre line.
    var inset: CGFloat
    var lineWidth: CGFloat

    func makeNSView(context: Context) -> OutlineView {
        OutlineView()
    }

    func updateNSView(_ view: OutlineView, context: Context) {
        view.color = color
        view.topRadius = topRadius
        view.bottomRadius = bottomRadius
        view.inset = inset
        view.lineWidth = lineWidth
        view.needsLayout = true
    }

    final class OutlineView: NSView {
        var color: NSColor = .systemBlue { didSet { shapeLayer.strokeColor = color.cgColor } }
        var topRadius: CGFloat = 0
        var bottomRadius: CGFloat = 0
        var inset: CGFloat = 0
        var lineWidth: CGFloat = 1 { didSet { shapeLayer.lineWidth = lineWidth } }

        private let shapeLayer = CAShapeLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.addSublayer(shapeLayer)
            shapeLayer.fillColor = nil
            shapeLayer.lineCap = .butt
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        /// Top-left origin so the path matches the SwiftUI shape's math.
        override var isFlipped: Bool { true }

        override func layout() {
            super.layout()
            shapeLayer.frame = bounds
            shapeLayer.path = NotchShape.waitLine(
                in: bounds, topRadius: topRadius, bottomRadius: bottomRadius, inset: inset
            ).cgPath
        }

        /// Animations leave with the layer, so restart it each time the
        /// view lands in a window.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = 1
            breathe.toValue = 0.35
            breathe.duration = 1.1
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shapeLayer.add(breathe, forKey: "breathe")
        }
    }
}
