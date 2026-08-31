import { pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";

/**
 * The pre-launch waitlist. Nothing writes to it now that the site downloads the app directly, but the addresses
 * collected before launch are real, so the table stays until they have been mailed.
 */
export const signups = pgTable("signups", {
    id: uuid().primaryKey().defaultRandom(),
    email: text().notNull().unique(),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
});
