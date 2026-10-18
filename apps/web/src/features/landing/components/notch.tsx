"use client";

import { motion } from "motion/react";
import { useEffect, useState } from "react";

import { useReducedMotion } from "@/lib/use-reduced-motion";

import { NotchContent } from "./notch-content";

const MINI = { width: 190, height: 32 };

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
        <motion.section
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
            tabIndex={0}
            aria-label="Notchlet usage preview. Focus or hover to expand the usage gauges."
            onFocus={() => setHovered(true)}
            onBlur={() => setHovered(false)}
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
                transition={
                    reducedMotion ? { duration: 0 } : mini ? { duration: 0.12 } : { duration: 0.25, delay: 0.08 }
                }
                style={{ width: expanded?.width }}
                className="pointer-events-none absolute top-0 left-1/2 w-full -translate-x-1/2 px-5 pt-14 pb-5 sm:pt-3"
            >
                <NotchContent hideHeaderOnMobile />
            </motion.div>
        </motion.section>
    );
}
