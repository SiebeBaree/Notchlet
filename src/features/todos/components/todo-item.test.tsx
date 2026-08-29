import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import type { Todo } from "@/lib/db/schema";

import { TodoItem } from "./todo-item";

const todo: Todo = {
    id: "8f14e45f-ceea-4b67-8a55-6a86e93ac3e1",
    title: "Write the docs",
    completed: false,
    createdAt: new Date(),
};

describe("TodoItem", () => {
    it("reports a toggle with the next completed state", async () => {
        const onToggle = vi.fn<(completed: boolean) => void>();
        render(<TodoItem todo={todo} onToggle={onToggle} onDelete={vi.fn<() => void>()} />);

        await userEvent.click(screen.getByRole("checkbox", { name: /mark "write the docs" as done/i }));
        expect(onToggle).toHaveBeenCalledWith(true);
    });

    it("reports deletion", async () => {
        const onDelete = vi.fn<() => void>();
        render(<TodoItem todo={todo} onToggle={vi.fn<(completed: boolean) => void>()} onDelete={onDelete} />);

        await userEvent.click(screen.getByRole("button", { name: /delete "write the docs"/i }));
        expect(onDelete).toHaveBeenCalledTimes(1);
    });
});
