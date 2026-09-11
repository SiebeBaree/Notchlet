# Changelog

## Unreleased

- Gauge time markers are off by default. Turn them on in settings, where an
  info icon explains what they mean. The marker is thicker, solid white and
  edged in black so it is easier to see on every gauge color.
- Claude Desktop token renewal reuses its storage key in memory. Failed
  Keychain reads pause until you retry in provider settings.

## 0.4.0

- The notch draws a line around itself while an agent is waiting on you. Blue
  when it finished, amber when it is asking something. One switch in settings
  installs a two-line hook into Claude Code, Codex, Cursor and OpenCode, and
  takes exactly those lines back out again. The line clears when you hover the
  notch, when you switch back to the terminal that runs the agent, or on that
  session's next prompt.
- A notification when a limit passes a mark you set. Pick a percent per limit
  in settings and the notch opens on the refresh that already happens, once
  per cycle, remembered across relaunches.
- Claude Code limits without the CLI. If Claude Desktop is signed in, Notchlet
  reads the token it saved for its Code tab. It never refreshes that token, so
  Desktop stays signed in.
- A provider with no gauges says why: not signed in, login expired, rate
  limited, or a plan that reports no limits, and what to do about it.
- Leaked secrets in your chats. Notchlet ships betterleaks and scans the
  Claude Code and Codex transcripts on this Mac for API keys and tokens, once
  when the Mac is idle and then hourly over what changed, never sending
  anything anywhere. A find opens the notch with the kind of key, its first and last
  characters, and a link to how to fix it. Ignore it or report a
  false positive. One toggle in settings turns scanning off.
- A notification, whether a limit passed a mark or a key was found, now
  stays in the notch until you deal with it, and opens with the same
  animation as a hover.
- Notchlet starts at login, on a fresh install and once after this update.
  The switch in settings still turns it off.
- The share image says how much you got for your subscription. Claude Code,
  Codex and Cursor report the plan behind their limits, so the 30-day image
  shows the cost at API prices as a multiple of what that plan costs, with
  no typing. The image is a quarter of the size it was and copies in a third
  of the time.
- Settings explain the secret scanner and the agent line behind an info
  icon instead of a line of text, the Claude sign-in picker no longer
  stretches its page, and a chosen alert mark is blue.
- The historic view shows $0 for an empty period and drops the "History
  since" note.

## 0.3.0

- A history pane behind the bars icon in the corner, or a click on any
  gauge: cost and tokens for today, 7 days and 30 days, a 12-month activity
  graph with each day's models on hover, a 30-day cost line, and every
  model's input and output tokens. Read from Claude Code's transcripts,
  Codex's session rollouts, OpenCode's message database and Cursor's usage
  export, sealed day by day into Notchlet's own archive, since Claude Code
  deletes transcripts after 30 days. Cost is what the tokens would cost at API list
  prices, never a bill.
- Share your usage as an image. The share icon in the corner opens a card
  with the numbers from the history pane, the activity graph or the cost line,
  and every model's tokens, rendered as a PNG you can copy or save. Pick the
  period, the theme and what to include.
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
