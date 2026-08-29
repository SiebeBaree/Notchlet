# Notchlet

[![CI](https://github.com/SiebeBaree/Notchlet/actions/workflows/ci.yml/badge.svg)](https://github.com/SiebeBaree/Notchlet/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)

Your agent limits, in the notch. Hover over it and Notchlet slides out with how much Claude Code and Codex usage you have left, both the rolling 5-hour window and the weekly one.

Claude Code hides this behind `/usage` and Codex behind `/status`. When you run agents all day, checking limits inside a terminal session you may not even have open is annoying. The top of your screen is the one place you already glance at constantly, so that's where the numbers should live.

## Status

Early. The notch shell works (a panel sits over the notch and expands on hover) and the provider architecture is in place, but both usage providers are stubs. If you want to help build the fun parts, now is the ideal time to jump in. See the [roadmap](#roadmap) and [CONTRIBUTING.md](CONTRIBUTING.md).

## Requirements

- macOS 14 or newer
- A notch is optional. On displays without one, Notchlet uses a virtual notch at the top center of the screen.

## Building from source

There are no binary releases yet.

```sh
git clone https://github.com/SiebeBaree/Notchlet.git
cd Notchlet
open Notchlet.xcodeproj
```

Run the `Notchlet` scheme (Xcode 26 or newer). The app has no dock icon. Look at the top of your screen and hover over the notch.

Or from the terminal:

```sh
xcodebuild build -scheme Notchlet -destination 'platform=macOS'
```

## How it reads usage

Notchlet never consumes usage to measure it. Each provider reads the same data the CLI itself shows you: the endpoint behind Claude Code's `/usage` and the rate-limit data behind Codex's `/status`. Credentials stay on your machine and Notchlet talks to nothing else. Both providers are unimplemented today; the plan lives in the doc comments of `Notchlet/Usage/`.

## Analytics

Notchlet sends anonymous usage stats to PostHog (EU cloud): a random UUID, hardware and app version context and events like "the notch was opened". It never sends your usage numbers, credentials, IP or anything that identifies you or your machine. The complete catalog of what leaves the machine is [`AnalyticsEvent.swift`](Notchlet/Analytics/AnalyticsEvent.swift). Turn it off with the "Share anonymous usage stats" toggle in the notch's settings. Debug builds send nothing.

## Updates

Notchlet checks for updates once a day through Sparkle. When one exists, a small download icon appears in the expanded notch and one click installs it. Updates are EdDSA-signed; the app refuses anything else.

## Roadmap

- [ ] Claude Code provider
- [ ] Codex provider
- [ ] Collapsed glance state: show the tightest remaining limit next to the notch without hovering
- [ ] Click-through for the transparent area around the collapsed notch
- [ ] Periodic background refresh
- [ ] Launch at login
- [ ] Signed, notarized releases and a Homebrew cask

## License

[MIT](LICENSE)
