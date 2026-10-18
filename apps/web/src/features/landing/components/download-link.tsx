"use client";

import type { ReactNode } from "react";

import { track } from "@/lib/analytics";

// Every Download button on the page. A plain anchor, not next/link: /download redirects to a file on GitHub, so it
// has to be a real navigation rather than a client-side route change.
export function DownloadLink({ className, children }: { className?: string; children: ReactNode }) {
    return (
        // oxlint-disable-next-line no-html-link-for-pages -- /download is a redirect to a file, not a page to route to.
        <a href="/download" className={className} onClick={() => track("download_started")}>
            {children}
        </a>
    );
}
