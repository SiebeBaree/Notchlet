"use client";

import { Settings } from "lucide-react";
import { motion, useReducedMotion } from "motion/react";
import Image from "next/image";
import { useEffect, useState } from "react";

const gauges = [
    { label: "5h", pct: 100, color: "#ffffff" },
    { label: "Weekly", pct: 90, color: "#30d158", resets: "Resets Sat 11:00 AM", status: "Plenty" },
    { label: "Fable", pct: 82, color: "#ffd60a", resets: "Resets Sat 11:00 AM", status: "On pace" },
] as const;

const MINI = { width: 190, height: 32 };

function Gauge({ gauge }: { gauge: (typeof gauges)[number] }) {
    const radius = 32;
    const circumference = 2 * Math.PI * radius;
    return (
        <div className="flex flex-col items-center">
            <span className="text-[13px] font-semibold text-white">{gauge.label}</span>
            <div className="relative mt-1.5 size-[72px]">
                <svg viewBox="0 0 72 72" className="size-full -rotate-90">
                    <circle cx="36" cy="36" r={radius} fill="none" stroke="#3a3a3c" strokeWidth="5.5" />
                    <circle
                        cx="36"
                        cy="36"
                        r={radius}
                        fill="none"
                        stroke={gauge.color}
                        strokeWidth="5.5"
                        strokeLinecap="round"
                        strokeDasharray={`${(circumference * gauge.pct) / 100} ${circumference}`}
                    />
                </svg>
                <div className="absolute inset-0 flex flex-col items-center justify-center">
                    <span className="text-[13px] leading-none font-bold text-white">{gauge.pct}%</span>
                    <span className="mt-0.5 text-[9px] leading-none text-white/60">left</span>
                </div>
            </div>
            {"resets" in gauge && (
                <>
                    <span className="mt-2 text-[10px] leading-none text-white/50">{gauge.resets}</span>
                    <span className="mt-1 text-[11px] leading-none font-medium" style={{ color: gauge.color }}>
                        {gauge.status}
                    </span>
                </>
            )}
        </div>
    );
}

// The hero notch. Expanded at the top of the page, it springs into a hardware-sized notch once scrolling
// starts and reopens on hover, Dynamic Island style. Touch devices keep it expanded since they can't hover.
export function Notch() {
    const [scrolled, setScrolled] = useState(false);
    const [hovered, setHovered] = useState(false);
    const [canMinimize, setCanMinimize] = useState(false);
    const [expanded, setExpanded] = useState<{ width: number; height: number }>();
    const reducedMotion = useReducedMotion();

    useEffect(() => {
        const readHoverCapability = () => setCanMinimize(window.matchMedia("(hover: hover)").matches);
        // Below sm the header row hides and the rings drop under the fixed menu bar, so the notch runs taller.
        const onResize = () =>
            setExpanded({
                width: Math.min(430, window.innerWidth * 0.85),
                height: window.innerWidth < 640 ? 215 : 190,
            });
        readHoverCapability();
        const onScroll = () => setScrolled(window.scrollY > 10);
        onResize();
        onScroll();
        window.addEventListener("resize", onResize);
        window.addEventListener("scroll", onScroll, { passive: true });
        return () => {
            window.removeEventListener("resize", onResize);
            window.removeEventListener("scroll", onScroll);
        };
    }, []);

    const mini = canMinimize && scrolled && !hovered;

    return (
        <motion.div
            initial={false}
            animate={{
                width: mini ? MINI.width : (expanded?.width ?? 430),
                height: mini ? MINI.height : (expanded?.height ?? 190),
                borderBottomLeftRadius: mini ? 12 : 28,
                borderBottomRightRadius: mini ? 12 : 28,
            }}
            transition={
                reducedMotion ? { duration: 0 } : { type: "spring", visualDuration: 0.4, bounce: mini ? 0 : 0.2 }
            }
            onMouseEnter={() => setHovered(true)}
            onMouseLeave={() => setHovered(false)}
            className="absolute top-0 left-1/2 z-20 max-w-[85vw] -translate-x-1/2 overflow-hidden bg-black shadow-[0_30px_70px_rgba(5,15,40,0.45),0_6px_18px_rgba(5,15,40,0.3)]"
        >
            <span
                aria-hidden
                className="absolute top-0 -left-[15px] size-[15px] bg-[radial-gradient(circle_at_0_100%,transparent_14.5px,#000_15px)]"
            />
            <span
                aria-hidden
                className="absolute top-0 -right-[15px] size-[15px] bg-[radial-gradient(circle_at_100%_100%,transparent_14.5px,#000_15px)]"
            />
            <motion.div
                initial={false}
                animate={{ opacity: mini ? 0 : 1 }}
                transition={mini ? { duration: 0.12 } : { duration: 0.25, delay: 0.08 }}
                style={{ width: expanded?.width }}
                className="pointer-events-none absolute top-0 left-1/2 w-full -translate-x-1/2 px-5 pt-14 pb-5 sm:pt-3"
            >
                <div className="hidden items-center justify-between sm:flex">
                    <span className="flex items-center gap-1.5 text-[13px] font-semibold text-white">
                        <Image src="/claude-ai-icon.svg" alt="" width={14} height={14} />
                        Claude
                    </span>
                    <Settings aria-hidden className="size-3.5 text-white/40" />
                </div>
                <div className="mt-1.5 grid grid-cols-3 gap-2">
                    {gauges.map((gauge) => (
                        <Gauge key={gauge.label} gauge={gauge} />
                    ))}
                </div>
            </motion.div>
        </motion.div>
    );
}
