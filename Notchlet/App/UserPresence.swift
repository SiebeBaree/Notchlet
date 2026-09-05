import AppKit
import CoreGraphics

/// Whether someone is at the Mac, for alerts that should land when they
/// are looking rather than pile up while they are away. Runs an action now
/// if there was input recently, otherwise on the first mouse event, through
/// a one-shot global monitor (mouse events need no permission, key events
/// would).
final class UserPresence {
    /// Input this recent means someone is at the Mac to see an alert.
    static let activeWithin: TimeInterval = 30

    private var monitor: Any?
    private var waiting: [() -> Void] = []

    /// Seconds since the last mouse or key event anywhere on the system.
    static var idleSeconds: TimeInterval {
        [CGEventType.mouseMoved, .keyDown, .leftMouseDown, .scrollWheel]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }

    func whenActive(_ action: @escaping () -> Void) {
        if Self.idleSeconds < Self.activeWithin {
            action()
            return
        }
        waiting.append(action)
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .scrollWheel]) {
            [weak self] _ in
            MainActor.assumeIsolated {
                self?.resumed()
            }
        }
    }

    private func resumed() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        let actions = waiting
        waiting = []
        for action in actions {
            action()
        }
    }
}
