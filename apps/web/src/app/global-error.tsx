"use client";

import * as Sentry from "@sentry/nextjs";
import { useEffect } from "react";

// Replaces the root layout when it crashes, so it must render its own <html> and stay dependency-free.
export default function GlobalError({ error }: { error: Error & { digest?: string } }) {
    useEffect(() => {
        Sentry.captureException(error);
    }, [error]);

    return (
        <html lang="en">
            <body
                style={{
                    fontFamily: "system-ui, sans-serif",
                    padding: "4rem 1.5rem",
                    maxWidth: "28rem",
                    margin: "0 auto",
                }}
            >
                <h1>Something went wrong</h1>
                <p>The error has been reported. Please reload the page.</p>
            </body>
        </html>
    );
}
