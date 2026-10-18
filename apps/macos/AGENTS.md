# Notchlet for macOS

Swift 6, SwiftUI for the views, AppKit for the window. One target, one test target with Swift Testing, no third-party Swift code except Sparkle for updates and the betterleaks binary for the scanner. The product is one person's daily driver first, so every change is judged on what it does to the notch while the user is working: what it costs while idle, what it shows without asking, and whether it ever touches the agent's login.

The product, its vocabulary and the repo-wide rules are in the root `AGENTS.md`.

## Commands

Run these from `apps/macos`.

```sh
./Scripts/fetch-betterleaks.sh                                   # once after cloning, the build fails without it
xcodebuild build -scheme Notchlet -destination 'platform=macOS'
xcodebuild test -scheme Notchlet -destination 'platform=macOS'   # Swift Testing
swiftformat .                                                    # CI lints with swiftformat --lint .
```

## Rules

- Never consume usage to measure it. Never talk to anything except a CLI's own local state and its own usage endpoint. The scanner never validates a key.
- Keychain reads and writes go through `/usr/bin/security`, never the Security framework.
- Nothing polls on its own timer when an existing refresh can carry it.
- Pure logic (geometry, parsing, timing, pricing) stays out of AppKit types so it has tests. UI plumbing mostly does not need tests.
- Every feature folder under `Notchlet/` owns its logic and its view. A new provider is one file plus a logo imageset, a line in `AppDelegate` and a parsing test over a real response.
- The Xcode project uses file-system-synced groups: a new file under `Notchlet/` or `NotchletTests/` is in the target. Never hand-edit the pbxproj for source files.
- Swift 6 language mode, main-actor default isolation. Static members of an actor default to main-actor isolation here, so parsing helpers are `nonisolated`.
- macOS 14 deployment target.
- Never edit `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION`. CI injects both.
- Do not launch a second Notchlet or drive the cursor on Siebe's Mac without asking. To eyeball a view, render it from a temporary test with `ImageRenderer` or an off-screen `NSWindow`.
