import { z } from "zod";

// Normalize before validating so " Me@Example.COM " and "me@example.com" collide on the unique index.
export const signupSchema = z.object({
    email: z
        .string()
        .trim()
        .toLowerCase()
        .max(254, "That email is too long.")
        .pipe(z.email("That does not look like an email.")),
});

export type SignupInput = z.input<typeof signupSchema>;
