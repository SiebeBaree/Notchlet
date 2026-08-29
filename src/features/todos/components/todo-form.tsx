"use client";

import { zodResolver } from "@hookform/resolvers/zod";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus } from "lucide-react";
import { useForm } from "react-hook-form";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ActionError, unwrap } from "@/lib/action/result";
import { toastActionError } from "@/lib/action/toast";
import { track } from "@/lib/analytics";

import { createTodo } from "../actions";
import { todoKeys } from "../keys";
import { createTodoSchema, type CreateTodoInput } from "../schema";

export function TodoForm() {
    const queryClient = useQueryClient();
    const form = useForm<CreateTodoInput>({
        resolver: zodResolver(createTodoSchema),
        defaultValues: { title: "" },
    });

    const create = useMutation({
        mutationFn: async (input: CreateTodoInput) => unwrap(await createTodo(input)),
        onSuccess: (_todo, input) => {
            track("todo_created", { title_length: input.title.length });
            form.reset();
            void queryClient.invalidateQueries({ queryKey: todoKeys.list });
        },
        onError: (error) => {
            const titleError = error instanceof ActionError ? error.fieldErrors?.title?.[0] : undefined;
            if (titleError) {
                form.setError("title", { message: titleError });
                return;
            }
            toastActionError(error);
        },
    });

    const titleError = form.formState.errors.title?.message;

    return (
        <form onSubmit={form.handleSubmit((input) => create.mutate(input))} noValidate>
            <div className="flex gap-2">
                <Input
                    {...form.register("title")}
                    placeholder="What needs doing?"
                    aria-label="New todo title"
                    aria-invalid={titleError ? true : undefined}
                    autoComplete="off"
                />
                <Button type="submit" disabled={create.isPending}>
                    <Plus data-icon="inline-start" />
                    Add
                </Button>
            </div>
            {titleError ? (
                <p role="alert" className="mt-2 text-sm text-destructive">
                    {titleError}
                </p>
            ) : null}
        </form>
    );
}
