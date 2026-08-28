# Notchlet

Native macOS notch app (Swift 6, SwiftUI, AppKit for windowing) that shows remaining Claude Code and Codex usage: the rolling 5-hour window and the weekly window. LSUIElement agent, no dock icon, no main window. Hovering the notch expands a panel out of it.

## Commands

- Build: `xcodebuild build -scheme Notchlet -destination 'platform=macOS'`
- Test: `xcodebuild test -scheme Notchlet -destination 'platform=macOS'` (Swift Testing, not XCTest)
- Format: `swiftformat .` (CI lints with `swiftformat --lint .`)

## Architecture

- `Notchlet/App/` entry point. `AppDelegate` wires providers into `UsageStore` and creates the window controller.
- `Notchlet/Notch/` the panel: `NotchPanel` (borderless non-activating NSPanel), `NotchWindowController` (positions it over the notch, virtual notch fallback for external displays), `NotchView` (SwiftUI, hover to expand), `NotchGeometry` (pure geometry, AppKit-free so it's unit-testable).
- `Notchlet/Usage/` `UsageProvider` protocol plus one implementation per agent CLI. Both providers are stubs that throw `notImplemented`; planned data sources are in their doc comments.

## Constraints

- The pbxproj uses file-system-synced groups (objectVersion 77). New files under `Notchlet/` or `NotchletTests/` join the target automatically; never hand-edit the pbxproj to add files.
- Swift 6 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency.
- Providers must never consume usage when fetching it, and must not talk to anything except the CLI's own local state and usage endpoints.
- Keep pure logic (geometry, parsing) out of AppKit types so it stays testable.
- macOS 14 deployment target.
