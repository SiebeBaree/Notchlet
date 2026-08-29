import "server-only";
import { neon } from "@neondatabase/serverless";
import { drizzle } from "drizzle-orm/neon-http";

import { env } from "@/lib/env/server";

import * as schema from "./schema";

let cached: ReturnType<typeof createDb> | undefined;

function createDb() {
    return drizzle(neon(env.DATABASE_URL), { schema, casing: "snake_case" });
}

/**
 * env guarantees DATABASE_URL exists, so no runtime check is needed here. Creation is lazy only so SKIP_ENV_VALIDATION
 * builds (which have no database) don't construct a client at import time.
 */
export function getDb() {
    cached ??= createDb();
    return cached;
}

export * from "./schema";
