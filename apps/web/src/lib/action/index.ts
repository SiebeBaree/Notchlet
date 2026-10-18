import "server-only";
import * as Sentry from "@sentry/nextjs";
import { headers } from "next/headers";
import { after } from "next/server";
import { z } from "zod";

import { logger } from "@/lib/logger";
import { checkRateLimit } from "@/lib/rate-limit";

import type { ActionResult } from "./result";

export type { ActionResult };

/**
 * Every server action goes through this factory. Without any per-action effort it guarantees:
 *
 * - the feature's Zod schema validates the input (never trust the client)
 * - lib/rate-limit.ts rate limits the caller per IP
 * - one canonical log line lands in Axiom: name, requestId, durationMs, ok
 * - unexpected errors go to Sentry tagged with the same requestId, and the client gets a generic message plus that
 *   requestId to quote to support. Internals never leak.
 *
 * Usage (in a "use server" file):
 *
 *   export const createTodo = createAction({
 *     name: "todos.create",
 *     schema: createTodoSchema,
 *     handler: async (input) => { ... },
 *   });
 */
export function createAction<TSchema extends z.ZodType, TData>(options: {
    /** Canonical event name, `<feature>.<verb>`, e.g. "todos.create". */
    name: string;
    schema: TSchema;
    /** Opt out only for actions that cannot be abused. */
    rateLimit?: boolean;
    handler: (input: z.output<TSchema>) => Promise<TData>;
}) {
    const { name, schema, rateLimit = true, handler } = options;

    return async function action(rawInput: z.input<TSchema>): Promise<ActionResult<TData>> {
        const requestId = (await headers()).get("x-request-id") ?? crypto.randomUUID();
        const startedAt = performance.now();
        const finish = (level: "info" | "warn" | "error", fields: Record<string, unknown>) => {
            logger[level](name, {
                requestId,
                durationMs: Math.round(performance.now() - startedAt),
                ...fields,
            });
        };

        try {
            const parsed = schema.safeParse(rawInput);
            if (!parsed.success) {
                finish("warn", { ok: false, reason: "invalid_input" });
                return {
                    ok: false,
                    error: "Invalid input.",
                    fieldErrors: z.flattenError(parsed.error).fieldErrors,
                };
            }

            if (rateLimit) {
                const limit = await checkRateLimit(name);
                if (!limit.ok) {
                    finish("warn", { ok: false, reason: "rate_limited" });
                    return {
                        ok: false,
                        error: `Too many requests. Try again in ${limit.retryAfterSeconds}s.`,
                    };
                }
            }

            const data = await handler(parsed.data);
            finish("info", { ok: true });
            return { ok: true, data };
        } catch (error) {
            Sentry.captureException(error, { tags: { action: name, requestId } });
            finish("error", {
                ok: false,
                reason: "exception",
                error: error instanceof Error ? error.message : String(error),
            });
            return { ok: false, error: "Something went wrong. Please try again.", requestId };
        } finally {
            after(() => logger.flush());
        }
    };
}
