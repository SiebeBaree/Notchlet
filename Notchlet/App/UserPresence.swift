import CoreGraphics
import Foundation

/// How long since the last mouse or key event, for the scan schedule
/// (mouse and key events need no permission to be timed, only to be read).
enum UserPresence {
    static var idleSeconds: TimeInterval {
        [CGEventType.mouseMoved, .keyDown, .leftMouseDown, .scrollWheel]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }
}
