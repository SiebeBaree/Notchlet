import { withSentryConfig } from "@sentry/nextjs";
import type { NextConfig } from "next";

// The per-request CSP lives in proxy.ts. These static headers apply to every response, including static assets.
const securityHeaders = [
    { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains" },
    { key: "X-Content-Type-Options", value: "nosniff" },
    { key: "X-Frame-Options", value: "DENY" },
    { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
    { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
    { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
];

const nextConfig: NextConfig = {
    typedRoutes: true,
    // Required by the PostHog proxy rewrites below.
    skipTrailingSlashRedirect: true,
    async rewrites() {
        return [
            {
                source: "/api/pipe/static/:path*",
                destination: "https://eu-assets.i.posthog.com/static/:path*",
            },
            { source: "/api/pipe/:path*", destination: "https://eu.i.posthog.com/:path*" },
        ];
    },
    async headers() {
        return [{ source: "/(.*)", headers: securityHeaders }];
    },
};

export default withSentryConfig(nextConfig, {
    org: process.env.SENTRY_ORG,
    project: process.env.SENTRY_PROJECT,
    authToken: process.env.SENTRY_AUTH_TOKEN,
    // `true` generates a random tunnel route per build, which blocklists cannot target.
    tunnelRoute: true,
    silent: true,
    telemetry: false,
    sourcemaps: { disable: !process.env.SENTRY_AUTH_TOKEN },
});
