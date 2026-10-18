"use client";

import type { MotionValue } from "motion/react";
import { motion, useScroll, useSpring, useTransform } from "motion/react";
import { useEffect, useRef, useState } from "react";

import { useReducedMotion } from "@/lib/use-reduced-motion";

import { FeatureBlock, features } from "./features";
import { Hero } from "./hero";

// Scrubbing the shrink over ~1.8 viewports leaves a beat at the end to read the features.
const SHRINK = [0.05, 0.6];
const SCREEN_WIDTH = 1280;
const SCREEN_HEIGHT = 800;
const DECK_HEIGHT = 40;

function ScrollFeature({
    progress,
    start,
    side,
    feature,
}: {
    progress: MotionValue<number>;
    start: number;
    side: "left" | "right";
    feature: (typeof features)[number];
}) {
    const opacity = useTransform(progress, [start, start + 0.13], [0, 1]);
    const x = useTransform(progress, [start, start + 0.13], [side === "left" ? -28 : 28, 0]);
    return (
        <motion.div style={{ opacity, x }}>
            <FeatureBlock feature={feature} align={side === "left" ? "right" : "left"} />
        </motion.div>
    );
}

// The fullscreen hero shrinks into the laptop. Mobile and reduced-motion layouts place features below it.
export function DeviceScroll() {
    const ref = useRef<HTMLDivElement>(null);
    const reducedMotion = useReducedMotion();
    const { scrollYProgress } = useScroll({ target: ref, offset: ["start start", "end end"] });
    // The spring keeps everything on the JS driver (motion's native ScrollTimeline mistracks the staggered
    // feature ranges) and smooths the scrub so wheel steps don't stutter the laptop.
    const progress = useSpring(scrollYProgress, { stiffness: 220, damping: 34, mass: 0.6 });
    const [viewport, setViewport] = useState({ width: 0, height: 0 });
    // Keep the revealed screen at 16:10. Cap the whole laptop at 840px wide and leave room for the features.
    const endScale = Math.min(
        0.6,
        (viewport.width * 0.52) / (SCREEN_WIDTH + 120),
        (viewport.height * 0.8) / (SCREEN_HEIGHT + 36 + DECK_HEIGHT),
    );
    const scale = useTransform(progress, SHRINK, [1, endScale]);
    const screenWidth = useTransform(progress, SHRINK, [viewport.width, SCREEN_WIDTH]);
    const screenHeight = useTransform(progress, SHRINK, [viewport.height, SCREEN_HEIGHT]);
    // The deck shifts the screen above the laptop's center at full size.
    const y = useTransform(progress, SHRINK, [DECK_HEIGHT / 2, 0]);

    // Below md the wrapper has no scroll room and scrollYProgress degenerates to 1, so pin the transforms
    // to their fullscreen values there instead of trusting the scroll math.
    const [cinematic, setCinematic] = useState(true);
    useEffect(() => {
        const mq = window.matchMedia("(min-width: 768px)");
        const update = () => {
            setCinematic(mq.matches);
            setViewport({ width: window.innerWidth, height: window.innerHeight });
        };
        update();
        window.addEventListener("resize", update);
        return () => window.removeEventListener("resize", update);
    }, []);

    return (
        <>
            <div ref={ref} className={reducedMotion ? "relative" : "relative md:h-[280vh]"}>
                <div className="sticky top-0 h-svh min-h-[720px] overflow-hidden bg-white md:min-h-0">
                    <div
                        aria-hidden
                        className="absolute inset-0 bg-[radial-gradient(52%_44%_at_50%_46%,#efeafd,transparent_72%)]"
                    />
                    <div className="relative flex h-full items-center justify-center">
                        <motion.div
                            style={{
                                scale: cinematic && !reducedMotion ? scale : 1,
                                y: cinematic && !reducedMotion ? y : DECK_HEIGHT / 2,
                            }}
                            className="flex shrink-0 flex-col items-center will-change-transform"
                        >
                            <div className="rounded-t-[26px] rounded-b-[10px] bg-[#0a0a0c] p-[18px] shadow-[0_32px_90px_-28px_rgba(23,21,31,0.5)]">
                                <motion.div
                                    style={{
                                        width: cinematic && !reducedMotion && viewport.width ? screenWidth : undefined,
                                        height:
                                            cinematic && !reducedMotion && viewport.height ? screenHeight : undefined,
                                    }}
                                    className="h-svh min-h-[720px] w-screen overflow-hidden rounded-[12px] md:min-h-0"
                                >
                                    <Hero />
                                </motion.div>
                            </div>
                            <div className="relative h-[40px] w-[calc(100%+84px)] rounded-b-[18px] border-t border-white/15 bg-linear-to-b from-[#55555c] via-[#303036] to-[#17171b]">
                                <div className="absolute top-0 left-1/2 h-[10px] w-[140px] -translate-x-1/2 rounded-b-[10px] bg-linear-to-b from-[#0c0c0e] to-[#2b2b30]" />
                            </div>
                        </motion.div>
                    </div>
                    {!reducedMotion && (
                        <>
                            <div className="absolute inset-y-0 left-0 hidden w-[24%] flex-col items-end justify-center gap-16 pr-6 pl-[max(1.5rem,3.5vw)] md:flex">
                                <ScrollFeature progress={progress} start={0.55} side="left" feature={features[0]} />
                                <ScrollFeature progress={progress} start={0.65} side="left" feature={features[1]} />
                            </div>
                            <div className="absolute inset-y-0 right-0 hidden w-[24%] flex-col items-start justify-center gap-16 pr-[max(1.5rem,3.5vw)] pl-6 md:flex">
                                <ScrollFeature progress={progress} start={0.6} side="right" feature={features[2]} />
                                <ScrollFeature progress={progress} start={0.7} side="right" feature={features[3]} />
                            </div>
                        </>
                    )}
                </div>
            </div>
            <section className={`bg-white px-6 pt-16 pb-12 ${reducedMotion ? "" : "md:hidden"}`}>
                <div className="mx-auto flex max-w-md flex-col gap-12">
                    {features.map((feature) => (
                        <FeatureBlock key={feature.title} feature={feature} />
                    ))}
                </div>
            </section>
        </>
    );
}
