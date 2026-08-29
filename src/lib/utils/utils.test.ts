import { describe, expect, it } from "vitest";

import { formatRelativeTime } from "./index";

describe("formatRelativeTime", () => {
    const now = new Date("2026-08-21T12:00:00Z");

    it.each([
        [new Date("2026-08-21T11:59:30Z"), "just now"],
        [new Date("2026-08-21T11:55:00Z"), "5m ago"],
        [new Date("2026-08-21T09:00:00Z"), "3h ago"],
        [new Date("2026-08-19T12:00:00Z"), "2d ago"],
        [new Date("2026-08-01T12:00:00Z"), "Aug 1, 2026"],
    ])("formats %s as %s", (date, expected) => {
        expect(formatRelativeTime(date, now)).toBe(expected);
    });
});
