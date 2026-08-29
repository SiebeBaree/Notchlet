"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { unwrap } from "@/lib/action/result";
import { toastActionError } from "@/lib/action/toast";
import { track } from "@/lib/analytics";
import type { Todo } from "@/lib/db/schema";

import { deleteTodo, listTodos, toggleTodo } from "../actions";
import { todoKeys } from "../keys";
import { TodoForm } from "./todo-form";
import { TodoItem } from "./todo-item";

/**
 * Owns the todos query and all mutations. The RSC page provides initialData so the first paint needs no client fetch;
 * afterwards TanStack Query keeps the list fresh through invalidation and optimistic updates.
 */
export function TodoList({ initialTodos }: { initialTodos: Todo[] }) {
    const queryClient = useQueryClient();

    const { data: todos } = useQuery({
        queryKey: todoKeys.list,
        queryFn: async () => unwrap(await listTodos()),
        initialData: initialTodos,
    });

    const setListData = (update: (current: Todo[]) => Todo[]) => {
        queryClient.setQueryData<Todo[]>(todoKeys.list, (current) => update(current ?? []));
    };

    const toggle = useMutation({
        mutationFn: async (input: { id: string; completed: boolean }) => unwrap(await toggleTodo(input)),
        onMutate: async ({ id, completed }) => {
            await queryClient.cancelQueries({ queryKey: todoKeys.list });
            const previous = queryClient.getQueryData<Todo[]>(todoKeys.list);
            setListData((current) => current.map((todo) => (todo.id === id ? { ...todo, completed } : todo)));
            return { previous };
        },
        onSuccess: (_todo, { completed }) => track(completed ? "todo_completed" : "todo_reopened"),
        onError: (error, _input, context) => {
            queryClient.setQueryData(todoKeys.list, context?.previous);
            toastActionError(error);
        },
        onSettled: () => queryClient.invalidateQueries({ queryKey: todoKeys.list }),
    });

    const remove = useMutation({
        mutationFn: async (input: { id: string }) => unwrap(await deleteTodo(input)),
        onMutate: async ({ id }) => {
            await queryClient.cancelQueries({ queryKey: todoKeys.list });
            const previous = queryClient.getQueryData<Todo[]>(todoKeys.list);
            setListData((current) => current.filter((todo) => todo.id !== id));
            return {
                previous,
                wasCompleted: previous?.find((todo) => todo.id === id)?.completed ?? false,
            };
        },
        onSuccess: (_data, _input, context) => track("todo_deleted", { was_completed: context.wasCompleted }),
        onError: (error, _input, context) => {
            queryClient.setQueryData(todoKeys.list, context?.previous);
            toastActionError(error);
        },
        onSettled: () => queryClient.invalidateQueries({ queryKey: todoKeys.list }),
    });

    const remaining = todos.filter((todo) => !todo.completed).length;

    return (
        <Card>
            <CardHeader>
                <CardTitle>
                    Todos
                    <span className="ml-2 text-sm font-normal text-muted-foreground">
                        {remaining} of {todos.length} left
                    </span>
                </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
                <TodoForm />
                {todos.length === 0 ? (
                    <p className="py-6 text-center text-sm text-muted-foreground">
                        Nothing here yet. Add your first todo.
                    </p>
                ) : (
                    <ul className="divide-y">
                        {todos.map((todo) => (
                            <TodoItem
                                key={todo.id}
                                todo={todo}
                                onToggle={(completed) => toggle.mutate({ id: todo.id, completed })}
                                onDelete={() => remove.mutate({ id: todo.id })}
                            />
                        ))}
                    </ul>
                )}
            </CardContent>
        </Card>
    );
}
