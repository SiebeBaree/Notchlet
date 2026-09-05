# Contributing to Notchlet

## Setup

You need Xcode 26 or newer and a Mac. Clone, fetch the secret scanner's binary, open the project and run the `Notchlet` scheme:

```sh
git clone https://github.com/SiebeBaree/Notchlet.git
cd Notchlet
./Scripts/fetch-betterleaks.sh
open Notchlet.xcodeproj
```

The script downloads [betterleaks](https://github.com/betterleaks/betterleaks) into the gitignored `Vendor/`, pinned by version and checksum. The build fails until it has run. There are no other dependencies to install; Sparkle comes in through Swift Package Manager.

Analytics need a PostHog key in `Config/Secrets.xcconfig`, which is gitignored. Without it the app builds and sends nothing, which is what you want while developing.

The app is an `LSUIElement` agent: no dock icon, no main window. After launching, hover over the notch (or the top center of an external display) to see it. Quit it from the settings behind the gear, there is no menu.

`AGENTS.md` at the repo root describes the project, its vocabulary and its rules. Read it before changing how a feature is put together.

## Adding a provider

Implement `UsageProvider` in a new file under `Notchlet/Usage/`, add a logo imageset and register it in `AppDelegate`. Two rules:

1. Fetching usage must never consume usage or count against a limit.
2. Read only what the CLI itself uses (local files, keychain, its own usage endpoint). No third-party services.

Add a parsing test against a real response from the endpoint, with anything personal removed.

## Style

- Swift 6 language mode with main-actor default isolation. Follow what the compiler tells you.
- Format with [SwiftFormat](https://github.com/nicklockwood/SwiftFormat): `swiftformat .` before committing. CI runs `swiftformat --lint`.
- Comments say why, never what. A type gets a doc comment only when its name and members do not say what it is, one or two sentences. An inline comment only for a reason the code cannot express: a platform quirk, another program's protocol, a number that was measured. No comment restates a name or narrates a past change.

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

## AI-written code

PRs written with an AI agent are welcome, this codebase is largely built that way. The bar does not move for them. You are responsible for every line: read the diff, run the tests, and know why each change is there. A PR with dead code, comments that narrate the diff, tests that assert nothing, or changes outside its title gets closed rather than reviewed.
