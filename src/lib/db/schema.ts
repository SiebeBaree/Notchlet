import { boolean, pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";

// Column names derive from the property names via `casing: "snake_case"`, set in lib/db/index.ts and drizzle.config.ts.
export const todos = pgTable("todos", {
    id: uuid().primaryKey().defaultRandom(),
    title: text().notNull(),
    completed: boolean().notNull().default(false),
    createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
});

export type Todo = typeof todos.$inferSelect;
