import { describe, expect, it } from "vitest";

import { createTodoSchema, toggleTodoSchema } from "./schema";

describe("createTodoSchema", () => {
    it("trims surrounding whitespace", () => {
        expect(createTodoSchema.parse({ title: "  buy milk  " })).toEqual({ title: "buy milk" });
    });

    it("rejects titles that are empty after trimming", () => {
        expect(createTodoSchema.safeParse({ title: "   " }).success).toBe(false);
    });

    it("rejects titles over 200 characters", () => {
        expect(createTodoSchema.safeParse({ title: "x".repeat(201) }).success).toBe(false);
    });
});

describe("toggleTodoSchema", () => {
    it("rejects non-uuid ids", () => {
        expect(toggleTodoSchema.safeParse({ id: "1; DROP TABLE todos", completed: true }).success).toBe(false);
    });
});
