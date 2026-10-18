import { defineConfig } from "drizzle-kit";

export default defineConfig({
    schema: "./src/lib/db/schema.ts",
    out: "./src/lib/db/migrations",
    dialect: "postgresql",
    casing: "snake_case",
    dbCredentials: {
        // Only needed for db:push / db:migrate / db:studio, not for db:generate.
        url: process.env.DATABASE_URL ?? "",
    },
});
