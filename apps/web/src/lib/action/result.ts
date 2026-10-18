// Client-safe: shared between server actions and the components that call them. Keep free of server-only imports.

export type ActionResult<T> =
    | { ok: true; data: T }
    | {
          ok: false;
          error: string;
          fieldErrors?: Partial<Record<string, string[]>>;
          requestId?: string;
      };

export class ActionError extends Error {
    readonly fieldErrors?: Partial<Record<string, string[]>>;
    /** Quote this to support / search it in Axiom and Sentry. */
    readonly requestId?: string;

    constructor(failure: Extract<ActionResult<unknown>, { ok: false }>) {
        super(failure.error);
        this.name = "ActionError";
        this.fieldErrors = failure.fieldErrors;
        this.requestId = failure.requestId;
    }
}

/**
 * Converts an ActionResult into TanStack Query's world: return data on success, throw ActionError on failure so
 * onError/error states fire.
 */
export function unwrap<T>(result: ActionResult<T>): T {
    if (!result.ok) throw new ActionError(result);
    return result.data;
}
