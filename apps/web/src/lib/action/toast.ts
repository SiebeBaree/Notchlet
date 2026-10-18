import { toast } from "sonner";

import { ActionError } from "./result";

/**
 * The app-wide convention for surfacing a failed action: the server's safe message, plus a short reference the user
 * can quote to support. The full id is searchable in Axiom and Sentry.
 */
export function toastActionError(error: unknown) {
    const message = error instanceof Error ? error.message : "Something went wrong.";
    const reference = error instanceof ActionError && error.requestId ? ` (ref: ${error.requestId.slice(0, 8)})` : "";
    toast.error(`${message}${reference}`);
}
