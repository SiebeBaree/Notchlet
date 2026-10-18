import "server-only";
import { Axiom } from "@axiomhq/js";
import { AxiomJSTransport, ConsoleTransport, Logger } from "@axiomhq/logging";
import { nextJsFormatters } from "@axiomhq/nextjs";

import { env } from "@/lib/env/server";

/**
 * Server-side structured logging, shipped to Axiom (console in local dev).
 *
 * Logging philosophy: one canonical log line per meaningful unit of work (a server action, an inbound request error),
 * with a stable event name and a small set of searchable fields: requestId, durationMs, ok. No debug spam, no payload
 * dumps. When Sentry reports an error or a customer writes in, filter Axiom by that requestId to reconstruct what
 * happened.
 */
export const logger = new Logger({
    transports:
        env.AXIOM_TOKEN && env.AXIOM_DATASET
            ? [
                  new AxiomJSTransport({
                      axiom: new Axiom({ token: env.AXIOM_TOKEN, url: "https://api.eu.axiom.co" }),
                      dataset: env.AXIOM_DATASET,
                  }),
              ]
            : [new ConsoleTransport({ prettyPrint: process.env.NODE_ENV === "development" })],
    formatters: nextJsFormatters,
});
