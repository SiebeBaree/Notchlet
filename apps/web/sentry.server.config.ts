import * as Sentry from "@sentry/nextjs";

import { env } from "@/lib/env/client";

/**
 * Sentry is the source of truth for errors, not a general telemetry sink. Axiom owns logs and PostHog owns product
 * analytics, so traces are sampled low, breadcrumbs are capped and PII stays out. What must be great is the error
 * itself: stack, requestId tag (set in lib/action) and release.
 *
 * Region: Sentry stores data where the DSN points. Create the project in the EU region for a *.de.sentry.io DSN.
 */
Sentry.init({
    dsn: env.NEXT_PUBLIC_SENTRY_DSN,
    enabled: Boolean(env.NEXT_PUBLIC_SENTRY_DSN),
    // On Vercel this distinguishes preview deploys from production; NODE_ENV would call both "production".
    environment: process.env.VERCEL_ENV ?? process.env.NODE_ENV,
    // Enough tracing to spot slow endpoints, not enough to drown in spans.
    tracesSampleRate: 0.1,
    maxBreadcrumbs: 30,
    sendDefaultPii: false,
    normalizeDepth: 5,
});
