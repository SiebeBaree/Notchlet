# Notchlet

Notchlet is a native macOS app that lives in the notch and shows how much of your AI coding agent limits is left. It supports Claude Code, Codex, Cursor and OpenCode. Hover the notch and it opens into a view with a gauge per limit, a pace verdict, a historic view of tokens and cost read from the CLIs' own logs, and a share view that turns those numbers into a PNG. It also opens by itself when a limit passes a mark you set or when the secret scanner finds a key in a chat, and draws a line around the notch while an agent is waiting on you.

Swift 6, SwiftUI for the views, AppKit for the window. One target, one test target with Swift Testing, no third-party Swift code except Sparkle for updates and the betterleaks binary for the scanner. The product is one person's daily driver first, so every change is judged on what it does to the notch while the user is working: what it costs while idle, what it shows without asking, and whether it ever touches the agent's login.

## What makes it different

CodexBar and OpenUsage put usage in the menu bar. Notchlet is different in ways that shape every decision:

- **It is in the notch.** No dock icon, no menu bar item, no window. The notch shows nothing until hovered, then everything happens inside its shape. A feature that needs its own window (the share editor is the one exception) is probably wrong.
- **It costs nothing while closed.** The panel window is sized to the notch itself while collapsed, so mouse movement anywhere else never reaches the app. Anything that animates while the notch is closed goes through Core Animation, never SwiftUI state. Measured idle CPU is zero and stays zero.
- **It never spends usage or touches the login.** Limits come from the same endpoints the CLIs read, with the credentials they already saved. Keychain items are read through `/usr/bin/security` so macOS never prompts. Only Claude Code's token is ever refreshed, and only after it expired, using Claude Code's own lock protocol so a running Claude Code is never signed out.
- **It reads the history the CLIs already keep.** No cloud, no account, no telemetry of usage numbers. Claude Code's transcripts, Codex's rollouts, OpenCode's database and Cursor's export are rolled into one row per day and model, and finished days are sealed into Notchlet's own archive because Claude Code deletes transcripts after 30 days.
- **It scans chats for leaked keys.** betterleaks runs on the Mac at background priority. It stores a hash and eight characters of a finding, never the key, and never checks a key against anyone's API.
- **It tells you when a limit passes a mark**, on the refresh that already happens, once per cycle, persisted across relaunches.
- **It shows when an agent is waiting.** The CLIs' own hooks report a stop or a question through a socket, and the notch grows a blue or amber line until you look, switch back to the terminal that runs the agent, or give it its next prompt.

## Vocabulary

Siebe's words, which are the words for user-facing text, plans and PR descriptions. Code names in the second column exist and stay, but do not leak into prose.

| Say | Code | Not |
| --- | --- | --- |
| provider (Claude Code, Codex, Cursor, OpenCode) | `UsageProvider` | agent, CLI, integration |
| agent | the process a provider's CLI runs | |
| limit (5-hour limit, weekly limit, monthly limit) | `UsageWindow` | window, quota, bucket |
| the notch (the whole UI) | `NotchView`, `NotchPanel` | panel, popup, card |
| view (usage view, historic view, share view, settings) | `UsagePane`, `HistoryPane` | pane, page, screen |
| gauge | `UsageRing` | ring, dial, circle |
| historic view | `HistoryPane` | history tab, usage history |
| spend, cost | `UsageLedger` | |
| run out, empty (the pace verdict: Plenty, On pace, Empty 1h early) | `BurnProjection` | pace, burn rate in prose |
| the PNG, the image | `ShareCard` | card |
| secret scanner, secrets, keys | `SecretScanner`, `SecretFinding` | leaks, findings in prose |
| notification (a limit passed a mark) | `UsageAlerts` | alert in prose |
| the line (around the notch while an agent waits) | `AgentWaits`, `WaitOutline` | agent alert, outline, border |
| host app (the terminal or editor that launched the agent) | `HostApp` | |
| the website, the homepage (notchlet.com, a separate repo) | | |
| CodexBar, OpenUsage (reference apps), Claude Code, T3 Code (harnesses), CodeRabbit (review bot) | | |
| release (a tag) | | |

## Commands

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
- Comments say why, never what. No comment restates a name or narrates a past change.
- No Co-Authored-By trailer on commits. PR titles are conventional commits, PRs are real, not drafts, rebased on `main`.
- Never edit `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION`. CI injects both.
- Do not launch a second Notchlet or drive the cursor on Siebe's Mac without asking. To eyeball a view, render it from a temporary test with `ImageRenderer` or an off-screen `NSWindow`.

## Releasing

Tagging is the release. CI archives, signs, notarizes, publishes the GitHub release with the DMG and deploys the Sparkle appcast. Nothing is built on a laptop.

1. Move the `Unreleased` entries in `CHANGELOG.md` under the new version and make sure everything shipped is in them.
2. Merge to `main` and wait for CI to be green.
3. Tag from `main`:

   ```sh
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

4. About twelve minutes later, update the cask in `SiebeBaree/homebrew-tap` with the new version and the DMG's `shasum -a 256`.

To rehearse without publishing, run the release workflow by hand from the Actions tab. It stops before creating the release or touching the feed.
