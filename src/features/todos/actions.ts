"use server";

import { eq } from "drizzle-orm";
import { revalidatePath } from "next/cache";
import { z } from "zod";

import { createAction } from "@/lib/action";
import { getDb, todos } from "@/lib/db";

import { getTodos } from "./queries";
import { createTodoSchema, deleteTodoSchema, toggleTodoSchema } from "./schema";

// Read action so TanStack Query can refetch client-side. RSCs use queries.getTodos directly instead.
export const listTodos = createAction({
    name: "todos.list",
    schema: z.void(),
    handler: () => getTodos(),
});

export const createTodo = createAction({
    name: "todos.create",
    schema: createTodoSchema,
    handler: async ({ title }) => {
        const [todo] = await getDb().insert(todos).values({ title }).returning();
        revalidatePath("/todos");
        return todo;
    },
});

export const toggleTodo = createAction({
    name: "todos.toggle",
    schema: toggleTodoSchema,
    handler: async ({ id, completed }) => {
        // A missing row means the todo was deleted in another tab. Not an error, the client's refetch will reconcile.
        const [todo] = await getDb().update(todos).set({ completed }).where(eq(todos.id, id)).returning();
        revalidatePath("/todos");
        return todo ?? null;
    },
});

export const deleteTodo = createAction({
    name: "todos.delete",
    schema: deleteTodoSchema,
    handler: async ({ id }) => {
        await getDb().delete(todos).where(eq(todos.id, id));
        revalidatePath("/todos");
    },
});
