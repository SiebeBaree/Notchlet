import type { Metadata } from "next";
import { connection } from "next/server";

import { getTodos, TodoList } from "@/features/todos";

export const metadata: Metadata = { title: "Your todos" };

export default async function TodosPage() {
    // The nonce CSP needs dynamic rendering. Awaiting a query does not opt out of prerendering, only connection() does.
    await connection();
    const todos = await getTodos();

    return (
        <main className="mx-auto max-w-md px-6 py-16">
            <TodoList initialTodos={todos} />
        </main>
    );
}
