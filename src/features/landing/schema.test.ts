import { describe, expect, it } from "vitest";

import { signupSchema } from "./schema";

describe("signupSchema", () => {
    it("normalizes surrounding whitespace and case", () => {
        const parsed = signupSchema.parse({ email: "  Me@Example.COM " });
        expect(parsed.email).toBe("me@example.com");
    });

    it("rejects a missing domain", () => {
        expect(signupSchema.safeParse({ email: "me@" }).success).toBe(false);
    });

    it("rejects an address past the 254 character limit", () => {
        const email = `${"a".repeat(250)}@example.com`;
        expect(signupSchema.safeParse({ email }).success).toBe(false);
    });
});
