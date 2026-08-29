import AppKit

/// Notchlet lives entirely in the notch: no windows, no dock icon, no menu
/// bar item. A plain AppKit entry point; AppDelegate builds everything.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
