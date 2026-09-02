# Changelog

## Unreleased

- Claude no longer goes stale while Claude Code is idle. An expired token is
  refreshed the way a second Claude Code process would do it, using Claude
  Code's own locks and write-back, so Claude Code stays signed in.
- A settings page per provider: pick how it signs in, see what it is using or
  why it cannot, and paste a Cursor session token or an OpenCode API key for
  machines where the app or CLI is not the source.

## 0.2.0

- Cursor and OpenCode usage, next to Claude Code and Codex. Cursor shows the
  monthly budget split across its two model pools. OpenCode shows the OpenCode
  Go windows, since Zen credits have no endpoint to read.
- Three providers at a time. Installed CLIs fill the slots in the order they
  register and the remaining toggles lock.
- Moving the mouse along the top of the screen no longer costs CPU while the
  notch is closed. The window is the size of the notch until you open it.
- A CLI you are not logged into says so instead of showing an error.

## 0.1.1

- No more keychain password prompts. Claude Code rotates its token every 8
  hours and rewrites its keychain item, which reset the permission each time.
  Notchlet now reads the item the same way Claude Code writes it.
- A Quit button in settings. There was no way to stop the app short of
  Activity Monitor.
- Picking a refresh interval no longer bounces you back to the usage view.

## 0.1.0

First release.

- Remaining Claude Code and Codex usage per rate-limit window, in the notch.
- A burn-rate verdict per window, so a number that looks fine but is being spent
  too fast says so.
- Hover the notch to expand. One active provider shows its full breakdown, two
  or three show a gauge each with hover drill-in.
- Works on displays without a notch, using a virtual one at the top centre.
- Auto-update through Sparkle, with a quiet icon in the notch instead of a popup.
- Anonymous analytics, off with one toggle in settings.
