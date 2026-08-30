"use client";

import { Fragment, useEffect, useState } from "react";

// Launch: Monday August 31 2026, 13:00 UTC+2.
const launchMs = Date.UTC(2026, 7, 31, 11, 0, 0);

function partsUntilLaunch(nowMs: number) {
    const total = Math.max(0, Math.floor((launchMs - nowMs) / 1000));
    return {
        days: Math.floor(total / 86400),
        hours: Math.floor((total % 86400) / 3600),
        minutes: Math.floor((total % 3600) / 60),
        seconds: total % 60,
    };
}

// The hero sits on the wallpaper and the closing section on a light gradient, so the same countdown ships two palettes.
const palette = {
    dark: {
        digit: "text-white [text-shadow:0_2px_16px_rgba(5,15,45,0.4)]",
        colon: "text-white/30 [text-shadow:0_2px_16px_rgba(5,15,45,0.4)]",
        label: "text-white/55",
    },
    light: { digit: "text-ink", colon: "text-ink-3/40", label: "text-ink-3" },
} as const;

export function Countdown({ surface = "dark" }: { surface?: keyof typeof palette }) {
    const tone = palette[surface];
    const [parts, setParts] = useState(() => partsUntilLaunch(Date.now()));

    useEffect(() => {
        const id = setInterval(() => setParts(partsUntilLaunch(Date.now())), 1000);
        return () => clearInterval(id);
    }, []);

    // Units that already hit zero drop off the front so the countdown never leads with a dead cell.
    const all = [
        [parts.days === 1 ? "day" : "days", String(parts.days), parts.days],
        ["hours", String(parts.hours).padStart(2, "0"), parts.hours],
        ["minutes", String(parts.minutes).padStart(2, "0"), parts.minutes],
        ["seconds", String(parts.seconds).padStart(2, "0"), parts.seconds],
    ] as const;
    const firstLive = all.findIndex(([, , raw]) => raw > 0);
    const cells = firstLive === -1 ? all.slice(-1) : all.slice(firstLive);

    return (
        <div className="flex items-start">
            {cells.map(([label, value], index) => (
                <Fragment key={label}>
                    {index > 0 && (
                        <span aria-hidden className={`text-3xl leading-none font-light sm:text-5xl ${tone.colon}`}>
                            :
                        </span>
                    )}
                    <div className="flex w-16 flex-col items-center sm:w-24">
                        {/* Server and client render a second or two apart; the interval corrects it right after hydration. */}
                        <span
                            suppressHydrationWarning
                            className={`text-3xl leading-none font-semibold tracking-tight tabular-nums sm:text-5xl ${tone.digit}`}
                        >
                            {value}
                        </span>
                        <span className={`mt-2.5 text-[10px] tracking-[0.14em] uppercase ${tone.label}`}>{label}</span>
                    </div>
                </Fragment>
            ))}
        </div>
    );
}
