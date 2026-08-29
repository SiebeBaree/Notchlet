# Notchlet

Native macOS notch app (Swift 6, SwiftUI, AppKit for windowing) that shows remaining agent CLI usage (Claude Code, Codex) per rate-limit window, with a burn-rate verdict per window. LSUIElement agent, no dock icon, no main window. Hovering the notch expands a panel out of it: one provider shows its full breakdown, two or three show a summary gauge each with hover drill-in. At most three providers are active at once.

## Commands

- Build: `xcodebuild build -scheme Notchlet -destination 'platform=macOS'`
- Test: `xcodebuild test -scheme Notchlet -destination 'platform=macOS'` (Swift Testing, not XCTest)
- Format: `swiftformat .` (CI lints with `swiftformat --lint .`)

## Architecture

- `Notchlet/App/` entry point. Plain AppKit lifecycle (`main.swift`, no SwiftUI App scene); `AppDelegate` wires providers into `UsageStore`, creates the window controller, the update controller and analytics.
- `Notchlet/Analytics/` anonymous PostHog analytics (EU cloud). `AnalyticsEvent` is the complete typed catalog of what leaves the machine; `Analytics` is the SDK wrapper (opt-out toggle, daily heartbeat, provider super properties); `DeviceInfo` gathers hardware context. Never call `identify()`, never send usage numbers or credentials. Disabled entirely in DEBUG builds. The project key is substituted into `Notchlet/Info.plist` from the gitignored `Config/Secrets.xcconfig`, so it is never in source; builds without that file send nothing.
- `Notchlet/Updates/` Sparkle auto-update. `UpdateController` suppresses all scheduled-update popups (gentle reminders); the notch shows an update icon instead and install hands off to Sparkle's standard flow. Sparkle keys live in the partial `Notchlet/Info.plist` (merged into the generated one; the feed 404s until the repo is public, which is intended).
- `Notchlet/Notch/` the panel: `NotchPanel` (borderless non-activating NSPanel), `NotchWindowController` (positions it over the notch, virtual notch fallback for external displays), `NotchView` (SwiftUI, hover to expand), `NotchGeometry` (pure geometry, AppKit-free so it's unit-testable).
- `Notchlet/Usage/` the provider system. `UsageProvider` is the base protocol; endpoint-backed providers adopt `HTTPUsageProvider` and only supply the endpoint URL, auth headers and response mapping (`fetchUsage` is a shared default). `CredentialSupport` has the common credential plumbing (home dir JSON, keychain items, JWT expiry). A new provider is one file plus a logo imageset, with a parsing test against a real response fixture.
- `BurnProjection` is the pace model, mirrored from CodexBar: average burn since the window started (elapsed derives from `resetsAt` and the window duration), no run-out verdict until 8% of the window has elapsed. Stateless; don't reintroduce sample history.
- Providers never refresh OAuth tokens: refresh tokens rotate, and rotating behind the CLI's back can invalidate its session. Expired login means no data until the user runs that CLI.

## Constraints

- The pbxproj uses file-system-synced groups (objectVersion 77). New files under `Notchlet/` or `NotchletTests/` join the target automatically; never hand-edit the pbxproj to add files.
- Swift 6 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency.
- Providers must never consume usage when fetching it, and must not talk to anything except the CLI's own local state and usage endpoints.
- Keep pure logic (geometry, parsing) out of AppKit types so it stays testable.
- macOS 14 deployment target.
