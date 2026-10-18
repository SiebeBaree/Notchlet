import { createEnv } from "@t3-oss/env-nextjs";
import { z } from "zod";

/**
 * Client-safe environment variables. Everything here is inlined into the browser bundle, so only NEXT_PUBLIC_* values
 * belong here. All are optional: each integration silently disables itself when its key is missing.
 */
export const env = createEnv({
    client: {
        NEXT_PUBLIC_POSTHOG_KEY: z.string().min(1).optional(),
        NEXT_PUBLIC_SENTRY_DSN: z.url().optional(),
    },
    experimental__runtimeEnv: {
        NEXT_PUBLIC_POSTHOG_KEY: process.env.NEXT_PUBLIC_POSTHOG_KEY,
        NEXT_PUBLIC_SENTRY_DSN: process.env.NEXT_PUBLIC_SENTRY_DSN,
    },
    emptyStringAsUndefined: true,
});
