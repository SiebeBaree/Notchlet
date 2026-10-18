import "server-only";
import { createEnv } from "@t3-oss/env-nextjs";
import { z } from "zod";

import { env as clientEnv } from "./client";

const isProd = process.env.NODE_ENV === "production";

/**
 * Server-only environment variables. The "server-only" import makes any accidental client-side import a build error
 * instead of a leaked secret. Extends the client env so server code can read everything from one object.
 *
 * Three tiers:
 * - DATABASE_URL: always required, the app cannot function without it.
 * - APP_URL and Upstash: required in production, optional in dev where localhost and the no-op limiter are fine.
 *   Rate limiting is a security control and canonical URLs decide SEO, so a forgotten variable must fail the deploy.
 * - Axiom: always optional. Missing observability degrades to console logging and you notice an empty dashboard,
 *   it does not open a hole.
 */
export const env = createEnv({
    extends: [clientEnv],
    server: {
        DATABASE_URL: z.url(),
        APP_URL: isProd ? z.url() : z.url().optional(),
        UPSTASH_REDIS_REST_URL: isProd ? z.url() : z.url().optional(),
        UPSTASH_REDIS_REST_TOKEN: isProd ? z.string().min(1) : z.string().min(1).optional(),
        AXIOM_TOKEN: z.string().min(1).optional(),
        AXIOM_DATASET: z.string().min(1).optional(),
    },
    experimental__runtimeEnv: {},
    emptyStringAsUndefined: true,
    // For builds that have no environment, e.g. CI and the e2e security suite: SKIP_ENV_VALIDATION=1 pnpm build
    skipValidation: Boolean(process.env.SKIP_ENV_VALIDATION),
});
