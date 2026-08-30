import { pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";

/**
 * Launch waitlist. One row per address: the unique constraint turns a repeat submit into a no-op instead of a
 * duplicate, which is why the action can use onConflictDoNothing and still report success.
 */
export const signups = pgTable("signups", {
    id: uuid().primaryKey().defaultRandom(),
    email: text().notNull().unique(),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
});
