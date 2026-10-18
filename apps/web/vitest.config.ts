import path from "node:path";

import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

export default defineConfig({
    plugins: [react()],
    test: {
        include: ["src/**/*.test.{ts,tsx}"],
        environment: "jsdom",
        // Required for Testing Library's automatic DOM cleanup between tests.
        globals: true,
        setupFiles: ["./test/setup.ts"],
    },
    resolve: {
        alias: {
            "@": path.resolve(import.meta.dirname, "src"),
            // The real package throws outside RSC. Unit tests run server modules in plain Node, so it becomes a no-op.
            "server-only": path.resolve(import.meta.dirname, "test/mocks/server-only.ts"),
        },
    },
});
