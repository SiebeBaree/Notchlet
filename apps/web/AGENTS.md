# notchlet-website

The marketing site for Notchlet, a macOS app that lives in the notch and shows your usage of AI tools like Claude Code, Codex, Cursor and OpenCode. Hover over the notch and it expands to show how much of your plan you have used.

Right now this is a single landing page counting down to launch. A login system arrives in a few weeks, which is why the database, rate limiting and the `(app)` route group are wired up but unused.

## Principles

- Yagni. Fight for the smallest change that makes the behavior correct. Do not add abstractions for imagined futures and do not preserve complexity just because it exists.
- Typesafety over defensiveness. `any` is banned (lint enforced). Let inference flow; if you fight the types, the design is probably wrong.
- Routes compose, features implement. A page awaits queries and renders feature components. When a page grows logic, move that logic into the feature.
- A lib entry starts as a single file. The moment it needs a test or a second file, it becomes a folder with the test inside.
- Comments only for what the code cannot show: framework magic, security trade-offs, policy, traps. Never restate the code. No em-dashes and no oxford commas anywhere, including comments.
- Run `pnpm typecheck && pnpm lint && pnpm test && pnpm format` before finishing any change. Lint warnings fail the build on purpose.
- Do not create documentation files (README, docs/) unless explicitly asked.

## Glossary

- **Feature**: a vertical slice under `features/` owning its schema, queries, actions and components. Client components import siblings directly; the feature barrel is server-only.
- **Page**: a route file under `app/`. Thin on purpose: it awaits queries and renders feature components. A new page should contain nothing else.
- **Server action**: a mutation built with the `createAction` factory. Adding a server action means schema validation, rate limiting, logging and error handling come along automatically.
- **Query**: a server-side read in a feature's `queries.ts`, called from pages. Reads are queries, writes are server actions.
- **Schema**: the Zod schema in a feature. One schema validates the form on the client and the server action on the server.

## Observability: three tools, three jobs

PostHog answers "what are users doing" (add custom events to the typed catalog in `lib/analytics.ts`, never call capture directly, keep properties anonymous). Sentry answers "what broke" (errors only, lean, no logs, no replay). Axiom answers "what happened around it" (canonical lines only, no payload dumps). Do not cross the streams: an expected failure is not a Sentry event and a debug print is not an Axiom line.

## Testing: when and what

Test the things that can be wrong in interesting ways. Zod schema edges, real logic in lib and dumb components with behavior worth pinning get colocated Vitest tests. Server components and server actions have no honest unit-test story, so they go untested; keep logic out of them. Do not write smoke tests that assert a page renders, regression tests for deleted features or tests that mock half the app; if a unit test needs heavy infrastructure mocking, the seam is wrong, move the logic. A fixed bug earns a regression test only when the bug was real logic, not glue.

## Things you need to know

- Every page renders dynamically because the CSP nonce requires a per-request render. `await connection()` is the explicit opt-in; awaiting a database call does not prevent static prerendering. Do not remove it, do not add static rendering back.
- The strict CSP means new external origins must be added deliberately. PostHog and Sentry traffic is proxied through our own origin precisely so the browser never talks to third parties.
- Importing server code into a client component is a build error via `server-only`. Type-only imports across that boundary are safe and lint-enforced (`import type`), and load-bearing: dropping the `type` keyword ships server code to the browser.
- Builds without an environment use `SKIP_ENV_VALIDATION=1`. Never weaken a required env var to optional to make a build pass; the fail-fast is the point.
- Formatting is oxfmt's job, including import order and Tailwind class order. Never hand-format or reorder imports.
- shadcn components under `components/ui` are generated. Add or update them with the shadcn CLI, do not hand-edit beyond what a change genuinely requires.
- There is no auth by design (the provider choice varies per project). The `(app)` route group marks where it slots in.

<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->
