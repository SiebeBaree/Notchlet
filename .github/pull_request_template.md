## What

<!-- One or two sentences. What problem does this solve? -->

## How

<!-- How you solved it. Screenshots or a screen recording for anything visual. -->

## Checklist

- [ ] App: `xcodebuild test -scheme Notchlet -destination 'platform=macOS'` and `swiftformat --lint .` pass in `apps/macos`
- [ ] Website: `pnpm typecheck && pnpm lint && pnpm format:check && pnpm test` pass in `apps/web`
- [ ] Title follows conventional commit style, e.g. `feat(usage): codex provider`
