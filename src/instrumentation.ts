import { createOnRequestError } from "@axiomhq/nextjs";
import * as Sentry from "@sentry/nextjs";
import type { Instrumentation } from "next";

import { logger } from "@/lib/logger";

export async function register() {
    if (process.env.NEXT_RUNTIME === "nodejs") {
        await import("../sentry.server.config");
    }
    if (process.env.NEXT_RUNTIME === "edge") {
        await import("../sentry.edge.config");
    }
}

const logRequestError = createOnRequestError(logger);

export const onRequestError: Instrumentation.onRequestError = async (error, request, context) => {
    Sentry.captureRequestError(error, request, context);
    await logRequestError(error, request, context);
};
