import "server-only";
import { Ratelimit } from "@upstash/ratelimit";
import { Redis } from "@upstash/redis";
import { headers } from "next/headers";

import { env } from "@/lib/env/server";

/**
 * One shared policy for all server actions: 20 requests per 10 seconds per IP per action. Add a separate Ratelimit
 * instance here if an endpoint ever needs its own budget (e.g. auth attempts).
 *
 * Without Upstash credentials (local dev) rate limiting is a no-op.
 *
 * Region: create the Redis database in an EU region. It is baked into UPSTASH_REDIS_REST_URL, nothing to set here.
 */
const limiter =
    env.UPSTASH_REDIS_REST_URL && env.UPSTASH_REDIS_REST_TOKEN
        ? new Ratelimit({
              redis: new Redis({ url: env.UPSTASH_REDIS_REST_URL, token: env.UPSTASH_REDIS_REST_TOKEN }),
              limiter: Ratelimit.slidingWindow(20, "10 s"),
              prefix: "rl",
          })
        : undefined;

export type RateLimitResult = { ok: true } | { ok: false; retryAfterSeconds: number };

export async function checkRateLimit(action: string): Promise<RateLimitResult> {
    if (!limiter) return { ok: true };
    const result = await limiter.limit(`${action}:${await clientIp()}`);
    if (result.success) return { ok: true };
    return {
        ok: false,
        retryAfterSeconds: Math.max(1, Math.ceil((result.reset - Date.now()) / 1000)),
    };
}

async function clientIp() {
    const forwardedFor = (await headers()).get("x-forwarded-for");
    return forwardedFor?.split(",")[0]?.trim() ?? "unknown";
}
