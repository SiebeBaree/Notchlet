# Contributing to Notchlet

## Setup

You need Xcode 26 or newer. Clone, open `Notchlet.xcodeproj`, run the `Notchlet` scheme. That's it, there are no dependencies.

The app is an `LSUIElement` agent: no dock icon, no main window. After launching, hover over the notch (or the top center of an external display) to see it.

## Project layout

```
Notchlet/
  App/        entry point and the delegate that builds every service
  Notch/      the panel over the notch: window, positioning, root view, settings, shared controls
  Usage/      provider protocol, models, the store and one provider per agent CLI
  History/    past usage read from the CLIs' logs, and its pane
  Secrets/    leaked keys in the CLIs' chats, and their pane
  Alerts/     threshold alerts, and their pane
  Agents/     the wait line fed by the CLIs' hooks
  Share/      the share card and its editor window
  Analytics/  anonymous PostHog events
  Updates/    Sparkle
NotchletTests/
```

Each feature folder owns its logic and its pane. `CLAUDE.md` at the repo root is the architecture doc; read it before changing how a feature is put together.

The Xcode project uses file-system-synced groups. Add a file to the right folder on disk and it is part of the target, no pbxproj edits needed. This keeps merge conflicts out of pull requests, so please don't restructure targets without opening an issue first.

## Adding a usage provider

Implement `UsageProvider` in a new file under `Notchlet/Usage/` and register it in `AppDelegate`. Two rules:

1. Fetching a snapshot must never consume usage or count against a limit.
2. Read only what the CLI itself uses (local files, keychain, its own usage endpoint). No third-party services.

## Style

- Swift 6 language mode with main-actor default isolation. Follow what the compiler tells you.
- Format with [SwiftFormat](https://github.com/nicklockwood/SwiftFormat): `swiftformat .` before committing. CI runs `swiftformat --lint`.
- Comments explain intent and constraints, not what the next line does.

## Tests

```sh
xcodebuild test -scheme Notchlet -destination 'platform=macOS'
```

Tests use Swift Testing. Keep them focused: pure logic like geometry and parsing deserves tests, UI plumbing mostly does not. Keep testable logic free of AppKit where you can (see `NotchGeometry`).

## Pull requests

- Title in conventional commit style: `feat(usage): claude code provider`.
- Open a real PR, not a draft.
- Rebase onto latest `main` before opening.
- One change per PR. Small PRs get reviewed fast.

For anything beyond a bug fix, open an issue first so we agree on direction before you write code.
