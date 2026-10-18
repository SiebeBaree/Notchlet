# Notchlet

Notchlet is a native macOS app that lives in the notch and shows how much of your AI coding agent limits is left. It supports Claude Code, Codex, Cursor and OpenCode. Hover the notch and it opens into a view with a gauge per limit, a pace verdict, a historic view of tokens and cost read from the CLIs' own logs, and a share view that turns those numbers into a PNG. It also opens by itself when a limit passes a mark you set or when the secret scanner finds a key in a chat, and draws a line around the notch while an agent is waiting on you.

## Layout

- `apps/macos` is the app: Swift, the Xcode project, its tests and scripts. Read `apps/macos/AGENTS.md` before changing it.
- `apps/web` is the website. Next.js on pnpm. Read `apps/web/AGENTS.md` before changing it.
- `docs/` holds the README's images.

The two apps share no code or tooling, so the root has no workspace setup. Each has its own CI workflow that only runs when its folder changes.

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
| the website, the homepage (notchlet.com, `apps/web`) | | |
| CodexBar, OpenUsage (reference apps), Claude Code, T3 Code (harnesses), CodeRabbit (review bot) | | |
| release (a tag) | | |

## Rules

- Comments say why, never what. No comment restates a name or narrates a past change.
- No Co-Authored-By trailer on commits. PR titles are conventional commits, PRs are real, not drafts, rebased on `main`.

## Releasing

Tagging releases the macOS app. CI archives, signs, notarizes, publishes the GitHub release with the DMG and deploys the Sparkle appcast. Nothing is built on a laptop.

1. Move the `Unreleased` entries in `CHANGELOG.md` under the new version and make sure everything shipped is in them.
2. Merge to `main` and wait for CI to be green.
3. Tag from `main`:

   ```sh
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

4. About twelve minutes later, update the cask in `SiebeBaree/homebrew-tap` with the new version and the DMG's `shasum -a 256`.

To rehearse without publishing, run the release workflow by hand from the Actions tab. It stops before creating the release or touching the feed.
