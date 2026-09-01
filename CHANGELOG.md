# Changelog

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
