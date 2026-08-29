import "server-only";
import { desc } from "drizzle-orm";

import { getDb, todos } from "@/lib/db";

export function getTodos() {
    return getDb().select().from(todos).orderBy(desc(todos.createdAt));
}
