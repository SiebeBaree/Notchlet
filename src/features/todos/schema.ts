import { z } from "zod";

export const createTodoSchema = z.object({
    title: z.string().trim().min(1, "Add a title first.").max(200, "Keep titles under 200 characters."),
});

export const toggleTodoSchema = z.object({
    id: z.uuid(),
    completed: z.boolean(),
});

export const deleteTodoSchema = z.object({
    id: z.uuid(),
});

export type CreateTodoInput = z.input<typeof createTodoSchema>;
export type ToggleTodoInput = z.input<typeof toggleTodoSchema>;
export type DeleteTodoInput = z.input<typeof deleteTodoSchema>;
