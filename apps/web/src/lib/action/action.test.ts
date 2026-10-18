import { beforeEach, describe, expect, it, vi } from "vitest";
import { z } from "zod";

type LogFn = (message: string, fields?: Record<string, unknown>) => void;

const captureException = vi.fn<(...args: unknown[]) => void>();
const checkRateLimit = vi.fn<(action: string) => Promise<{ ok: true } | { ok: false; retryAfterSeconds: number }>>();
const log = {
    info: vi.fn<LogFn>(),
    warn: vi.fn<LogFn>(),
    error: vi.fn<LogFn>(),
    flush: vi.fn<() => Promise<void>>(),
};

vi.mock("next/headers", () => ({
    headers: async () => new Headers({ "x-request-id": "req-123" }),
}));
vi.mock("next/server", () => ({ after: vi.fn<(task: () => unknown) => void>() }));
vi.mock("@sentry/nextjs", () => ({
    captureException: (...args: unknown[]) => captureException(...args),
}));
vi.mock("@/lib/rate-limit", () => ({
    checkRateLimit: (action: string) => checkRateLimit(action),
}));
vi.mock("@/lib/logger", () => ({ logger: log }));

const { createAction } = await import("./index");

const echo = createAction({
    name: "test.echo",
    schema: z.object({ value: z.string().min(1) }),
    handler: async ({ value }) => value.toUpperCase(),
});

beforeEach(() => {
    vi.clearAllMocks();
    checkRateLimit.mockResolvedValue({ ok: true });
});

describe("createAction", () => {
    it("returns handler data for valid input", async () => {
        await expect(echo({ value: "hi" })).resolves.toEqual({ ok: true, data: "HI" });
        expect(log.info).toHaveBeenCalledWith("test.echo", expect.objectContaining({ ok: true, requestId: "req-123" }));
    });

    it("rejects invalid input with field errors, without calling the handler", async () => {
        const result = await echo({ value: "" });
        expect(result).toMatchObject({ ok: false, error: "Invalid input." });
        if (result.ok) throw new Error("expected failure");
        expect(result.fieldErrors?.value).toBeDefined();
        expect(checkRateLimit).not.toHaveBeenCalled();
    });

    it("stops rate-limited callers before the handler runs", async () => {
        checkRateLimit.mockResolvedValue({ ok: false, retryAfterSeconds: 7 });
        const result = await echo({ value: "hi" });
        expect(result).toEqual({ ok: false, error: "Too many requests. Try again in 7s." });
    });

    it("reports thrown errors to Sentry and returns a safe message with the requestId", async () => {
        const boom = createAction({
            name: "test.boom",
            schema: z.object({}),
            handler: async () => {
                throw new Error("db exploded: secret details");
            },
        });

        const result = await boom({});
        expect(result).toEqual({
            ok: false,
            error: "Something went wrong. Please try again.",
            requestId: "req-123",
        });
        expect(captureException).toHaveBeenCalledWith(expect.any(Error), {
            tags: { action: "test.boom", requestId: "req-123" },
        });
        expect(log.error).toHaveBeenCalledWith(
            "test.boom",
            expect.objectContaining({ reason: "exception", error: "db exploded: secret details" }),
        );
    });

    it("skips rate limiting when disabled", async () => {
        const open = createAction({
            name: "test.open",
            schema: z.void(),
            rateLimit: false,
            handler: async () => "ok",
        });

        await expect(open()).resolves.toEqual({ ok: true, data: "ok" });
        expect(checkRateLimit).not.toHaveBeenCalled();
    });
});
