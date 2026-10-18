import * as Sentry from "@sentry/nextjs";

import { env } from "@/lib/env/client";

// Mirrors sentry.server.config.ts. See the rationale there.
Sentry.init({
    dsn: env.NEXT_PUBLIC_SENTRY_DSN,
    enabled: Boolean(env.NEXT_PUBLIC_SENTRY_DSN),
    environment: process.env.VERCEL_ENV ?? process.env.NODE_ENV,
    tracesSampleRate: 0.1,
    maxBreadcrumbs: 30,
    sendDefaultPii: false,
});
