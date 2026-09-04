"use client";

import type { CSSProperties } from "react";
import { useEffect, useState } from "react";

import { DownloadLink } from "./download-link";

// The swoop silhouette lives in globals.css (.menu-tab). Keeping it one element per tab is what keeps the backdrop
// blur uniform across the curve.
const segmentClass =
    "menu-tab pointer-events-auto flex items-center bg-(--seg) text-[13px] backdrop-blur-xl transition-colors duration-300";

// Two tabs hanging from the top corners, shaped like the ends of the macOS menu bar. Fixed so they ride along
// while scrolling; over the hero they blend with the wallpaper, past it they turn into light glass over the page.
// Pages without the dark hero pass `light` and start in the glass state.
export function MenuBar({ light = false }: { light?: boolean }) {
    const [scrolled, setScrolled] = useState(light);

    useEffect(() => {
        if (light) return;
        // Flip to light glass only once the shrinking hero has ceded most of the viewport to the white page.
        const onScroll = () => setScrolled(window.scrollY > window.innerHeight * 0.75);
        onScroll();
        window.addEventListener("scroll", onScroll, { passive: true });
        return () => window.removeEventListener("scroll", onScroll);
    }, [light]);

    return (
        <nav
            // Tinted rather than white when scrolled: a white tab on the white page reads as floating text.
            style={{ "--seg": scrolled ? "rgba(228,224,241,0.85)" : "rgba(12,14,22,0.4)" } as CSSProperties}
            className={`pointer-events-none fixed inset-x-0 top-0 z-50 flex h-[46px] items-stretch justify-between transition-colors duration-300 ${
                scrolled ? "text-ink" : "text-white/90"
            }`}
        >
            <div className={`${segmentClass} menu-tab-start pr-[58px] pl-4 sm:pl-6`}>
                <span className="flex items-center gap-2 font-semibold">
                    <span aria-hidden className="h-[13px] w-5 rounded-[4px_4px_7px_7px] bg-current opacity-90" />
                    Notchlet
                </span>
            </div>
            <div className={`${segmentClass} menu-tab-end pr-4 pl-[58px] sm:pr-6`}>
                <DownloadLink className="font-medium opacity-85 transition-opacity hover:opacity-100">
                    Download
                </DownloadLink>
            </div>
        </nav>
    );
}
