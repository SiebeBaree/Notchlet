import { type NextRequest, NextResponse } from "next/server";

/**
 * Runs on every page request (see matcher below). Two jobs:
 *
 * 1. CSP with a per-request nonce. Next.js reads the Content-Security-Policy request header and applies the nonce to
 *    every script it renders, so script-src needs no 'unsafe-inline'. This forces dynamic rendering on all pages, an
 *    accepted trade-off for a strict CSP.
 * 2. A request id, readable via headers() in server code and echoed on the response. It ties together the Axiom log
 *    line, the Sentry event and the reference a user can quote to support.
 */
export function proxy(request: NextRequest) {
    const nonce = Buffer.from(crypto.randomUUID()).toString("base64");
    const requestId = crypto.randomUUID();
    const isDev = process.env.NODE_ENV === "development";

    const csp = [
        "default-src 'self'",
        // 'strict-dynamic': scripts loaded by nonce-approved scripts (Next chunks, PostHog's lazy-loaded modules) are
        // trusted transitively. 'unsafe-eval' is dev-only: React uses eval for server error overlays.
        `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${isDev ? " 'unsafe-eval'" : ""}`,
        // 'unsafe-inline' for styles is deliberate: Radix and Sonner position and animate via inline style attributes,
        // which nonces cannot cover. Script injection stays fully blocked, which is what matters.
        "style-src 'self' 'unsafe-inline'",
        "img-src 'self' blob: data:",
        "font-src 'self'",
        // PostHog is proxied through /api/pipe and Sentry through its tunnel route, so the browser only talks to our
        // origin. ws: is dev-only (HMR).
        `connect-src 'self'${isDev ? " ws:" : ""}`,
        "worker-src 'self' blob:",
        "object-src 'none'",
        "base-uri 'self'",
        "form-action 'self'",
        "frame-ancestors 'none'",
        ...(isDev ? [] : ["upgrade-insecure-requests"]),
    ].join("; ");

    const requestHeaders = new Headers(request.headers);
    requestHeaders.set("x-nonce", nonce);
    requestHeaders.set("x-request-id", requestId);
    requestHeaders.set("Content-Security-Policy", csp);

    const response = NextResponse.next({ request: { headers: requestHeaders } });
    response.headers.set("Content-Security-Policy", csp);
    response.headers.set("x-request-id", requestId);
    return response;
}

export const config = {
    matcher: [
        // Everything except API routes (incl. the PostHog proxy under /api/pipe), Next internals, static files and
        // next/link prefetches. None of those render documents.
        {
            source: "/((?!api|_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico)$).*)",
            missing: [
                { type: "header", key: "next-router-prefetch" },
                { type: "header", key: "purpose", value: "prefetch" },
            ],
        },
    ],
};
