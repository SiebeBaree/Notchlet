import * as Sentry from "@sentry/nextjs";
import posthog from "posthog-js";

import { env } from "@/lib/env/client";

Sentry.init({
    dsn: env.NEXT_PUBLIC_SENTRY_DSN,
    enabled: Boolean(env.NEXT_PUBLIC_SENTRY_DSN),
    // The NEXT_PUBLIC_ variant of VERCEL_ENV, inlined at build time so the browser bundle gets the same value.
    environment: process.env.NEXT_PUBLIC_VERCEL_ENV ?? process.env.NODE_ENV,
    tracesSampleRate: 0.1,
    maxBreadcrumbs: 30,
    sendDefaultPii: false,
    // No replay integration: PostHog owns session replay. One recording of the user is enough, and Sentry replays are
    // the heaviest thing the SDK ships.
    ignoreErrors: [
        // Browser quirks that fire without any actual breakage.
        "ResizeObserver loop limit exceeded",
        "ResizeObserver loop completed with undelivered notifications",
        // The user navigated away or lost connectivity mid-request.
        "Failed to fetch",
        "NetworkError when attempting to fetch a resource",
        "Load failed",
    ],
    denyUrls: [/^chrome-extension:\/\//i, /^moz-extension:\/\//i, /^safari-extension:\/\//i],
});

// oxlint-disable-next-line import/namespace -- exists in the browser export, which the import plugin doesn't resolve
export const onRouterTransitionStart = Sentry.captureRouterTransitionStart;

if (env.NEXT_PUBLIC_POSTHOG_KEY) {
    posthog.init(env.NEXT_PUBLIC_POSTHOG_KEY, {
        // First-party proxy (see rewrites in next.config.ts) so ad blockers don't eat the data.
        api_host: "/api/pipe",
        ui_host: "https://eu.posthog.com",
        defaults: "2026-05-30",
        capture_exceptions: false,
    });
}
