# Notchlet

Native macOS notch app (Swift 6, SwiftUI, AppKit for windowing) that shows remaining agent CLI usage (Claude Code, Codex, Cursor, OpenCode) per rate-limit window, with a burn-rate verdict per window. LSUIElement agent, no dock icon, no main window. Hovering the notch expands a panel out of it: one provider shows its full breakdown, two or three show a summary gauge each with hover drill-in. At most three providers are active at once (`UsageStore.maxActiveProviders`); installed CLIs fill the slots in registration order and the settings toggles lock at the cap.

## Commands

- Build: `xcodebuild build -scheme Notchlet -destination 'platform=macOS'`
- Test: `xcodebuild test -scheme Notchlet -destination 'platform=macOS'` (Swift Testing, not XCTest)
- Format: `swiftformat .` (CI lints with `swiftformat --lint .`)

## Architecture

- `Notchlet/App/` entry point. Plain AppKit lifecycle (`main.swift`, no SwiftUI App scene); `AppDelegate` wires providers into `UsageStore`, creates the window controller, the update controller and analytics.
- `Notchlet/Analytics/` anonymous PostHog analytics (EU cloud). `AnalyticsEvent` is the complete typed catalog of what leaves the machine; `Analytics` is the SDK wrapper (opt-out toggle, daily heartbeat, provider super properties); `DeviceInfo` gathers hardware context. Never call `identify()`, never send usage numbers or credentials. Disabled entirely in DEBUG builds. The project key is substituted into `Notchlet/Info.plist` from the gitignored `Config/Secrets.xcconfig`, so it is never in source; builds without that file send nothing.
- `Notchlet/Updates/` Sparkle auto-update. `UpdateController` suppresses all scheduled-update popups (gentle reminders); the notch shows an update icon instead and install hands off to Sparkle's standard flow. Sparkle keys live in the partial `Notchlet/Info.plist` (merged into the generated one; the feed 404s until the repo is public, which is intended).
- `Notchlet/Notch/` the panel: `NotchPanel` (borderless non-activating NSPanel; it must be able to become key or the settings switches collapse the panel instead of toggling), `NotchWindowController` (positions it over the notch, virtual notch fallback for external displays), `NotchView` (SwiftUI, hover to expand), `NotchGeometry` (pure geometry, AppKit-free so it's unit-testable). The window is sized to the bare notch while collapsed and grows to `panelSize` only while expanded: every cursor move inside the window costs a SwiftUI hover hit-test, so the window is never larger than what it draws. The hosting view has `sizingOptions = []` because the controller owns the frame.
- `Notchlet/Usage/` the provider system. `UsageProvider` is the base protocol; endpoint-backed providers adopt `HTTPUsageProvider` and only supply the endpoint URL, auth headers and response mapping (`fetchUsage` is a shared default; 401/403 map to `notAvailable`). `CredentialSupport` has the common credential plumbing (home dir JSON, keychain items, Electron SQLite state, JWT claims). Keychain items are read by spawning `/usr/bin/security`, never through the Security framework: the CLI wrote the item with that tool so it stays on the access list, whereas a read as Notchlet prompts for the keychain password again after every token rotation (Claude Code rotates every 8 hours). Claude Code's credentials are cached until they expire so that read costs one process per token rather than one per poll; a rejection drops the cache and retries once, so a rotated token never shows as an error. Cursor's token is read from its `state.vscdb` by spawning `/usr/bin/sqlite3` read-only, so the app's database is never locked or modified. A new provider is one file plus a logo imageset and a line in `AppDelegate`, with a parsing test against a real response fixture.
- Windows are whatever the plan meters: rolling sessions, weeks, a billing cycle (Cursor) or model pools on one cycle (Cursor's "Cursor models" and "Other models", Claude's per-model weekly). `UsageSnapshot.primaryWindow` is the shortest window, first among equals, so a provider whose windows share one cycle lists the headline first. OpenCode shows only OpenCode Go windows: Zen credits have no key-authenticated endpoint and browser cookies are off limits.
- Refresh cadence: `UsageStore` polls slowly while the panel is closed (user setting, 3-30 min, default 10) and every 60s while open; opening the panel makes anything older than 60s due immediately. `RefreshSchedule` is the pure per-provider timing model: 30s minimum spacing, Retry-After/exponential backoff on 429, flat 2 min retry on other errors. The panel footer labels data age past 2 min and names a rate-limited provider with its retry time.
- `BurnProjection` is the pace model, mirrored from CodexBar: average burn since the window started (elapsed derives from `resetsAt` and the window duration), no run-out verdict until 8% of the window has elapsed. Stateless; don't reintroduce sample history.
- Providers never refresh OAuth tokens: refresh tokens rotate, and rotating behind the CLI's back can invalidate its session. Expired login means no data until the user runs that CLI.

## Releases

- Tagging is the release. `git push origin vX.Y.Z` runs `.github/workflows/release.yml`, which archives, notarizes, builds a DMG, publishes the GitHub release and deploys the Sparkle appcast to Pages. Nothing is built from a laptop. See `RELEASING.md`.
- Never hand-edit `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION`; CI injects both from the tag and the run number. Sparkle compares `CURRENT_PROJECT_VERSION`, so a stale value hides the update from everyone.
- `SUFeedURL` is compiled into every shipped binary and can never change. Front it with a redirect if a custom domain is ever wanted.
- The app icon is generated: `Scripts/AppIcon.svg` (the website icon, viewBox widened to inset it to the macOS icon grid) rendered by `Scripts/make-appicon.sh`. Edit the SVG and re-run the script, never the PNGs.

## Constraints

- The pbxproj uses file-system-synced groups (objectVersion 77). New files under `Notchlet/` or `NotchletTests/` join the target automatically; never hand-edit the pbxproj to add files.
- Swift 6 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency.
- Providers must never consume usage when fetching it, and must not talk to anything except the CLI's own local state and usage endpoints.
- Keep pure logic (geometry, parsing) out of AppKit types so it stays testable.
- macOS 14 deployment target.
