"use server";

import { createAction } from "@/lib/action";
import { getDb, signups } from "@/lib/db";

import { signupSchema } from "./schema";

export const signUpForLaunch = createAction({
    name: "landing.signup",
    schema: signupSchema,
    handler: async ({ email }) => {
        // Signing up twice is not a mistake worth surfacing, so a repeat address succeeds quietly.
        await getDb().insert(signups).values({ email }).onConflictDoNothing();
    },
});
