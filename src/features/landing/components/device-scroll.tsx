"use client";

import type { MotionValue } from "motion/react";
import { motion, useScroll, useSpring, useTransform } from "motion/react";
import { useEffect, useRef, useState } from "react";

import { FeatureBlock, features } from "./features";
import { Hero } from "./hero";

// Scrubbing the shrink over ~1.8 viewports leaves a beat at the end to read the features.
const SHRINK = [0.05, 0.6];
const END_SCALE = 0.42;

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

// The hero is the Mac's screen. Scrolling scales it down until the chassis around it (bezel and deck, parked
// just offscreen at full size) comes into view, then the features fade in beside the laptop. Below md there is
// no scroll room, so progress stays 0 and this renders as a plain fullscreen hero with features stacked after.
export function DeviceScroll() {
    const ref = useRef<HTMLDivElement>(null);
    const { scrollYProgress } = useScroll({ target: ref, offset: ["start start", "end end"] });
    // The spring keeps everything on the JS driver (motion's native ScrollTimeline mistracks the staggered
    // feature ranges) and smooths the scrub so wheel steps don't stutter the laptop.
    const progress = useSpring(scrollYProgress, { stiffness: 220, damping: 34, mass: 0.6 });
    const scale = useTransform(progress, SHRINK, [1, END_SCALE]);
    // At full size the screen sits 13px above the laptop's center, so nudge down to fill the viewport exactly.
    const y = useTransform(progress, SHRINK, [13, 0]);

    // Below md the wrapper has no scroll room and scrollYProgress degenerates to 1, so pin the transforms
    // to their fullscreen values there instead of trusting the scroll math.
    const [cinematic, setCinematic] = useState(true);
    useEffect(() => {
        const mq = window.matchMedia("(min-width: 768px)");
        const update = () => setCinematic(mq.matches);
        update();
        mq.addEventListener("change", update);
        return () => mq.removeEventListener("change", update);
    }, []);

    return (
        <>
            <div ref={ref} className="relative md:h-[280vh]">
                <div className="sticky top-0 h-svh overflow-hidden bg-white">
                    <div
                        aria-hidden
                        className="absolute inset-0 bg-[radial-gradient(52%_44%_at_50%_46%,#efeafd,transparent_72%)]"
                    />
                    <div className="relative flex h-full items-center justify-center">
                        <motion.div
                            style={{ scale: cinematic ? scale : 1, y: cinematic ? y : 13 }}
                            className="flex shrink-0 flex-col items-center will-change-transform"
                        >
                            <div className="rounded-t-[26px] rounded-b-[10px] bg-[#0a0a0c] p-[18px] shadow-[0_32px_90px_-28px_rgba(23,21,31,0.5)]">
                                <div className="h-svh w-screen overflow-hidden rounded-[12px]">
                                    <Hero />
                                </div>
                            </div>
                            <div className="relative h-[26px] w-[calc(100vw+120px)] rounded-b-[16px] bg-linear-to-b from-[#3c3c42] via-[#232327] to-[#111114]">
                                <div className="absolute top-0 left-1/2 h-[10px] w-[140px] -translate-x-1/2 rounded-b-[10px] bg-linear-to-b from-[#0c0c0e] to-[#2b2b30]" />
                            </div>
                        </motion.div>
                    </div>
                    <div className="absolute inset-y-0 left-0 hidden w-[27%] flex-col items-end justify-center gap-16 pr-6 pl-[max(1.5rem,3.5vw)] md:flex">
                        <ScrollFeature progress={progress} start={0.55} side="left" feature={features[0]!} />
                        <ScrollFeature progress={progress} start={0.65} side="left" feature={features[1]!} />
                    </div>
                    <div className="absolute inset-y-0 right-0 hidden w-[27%] flex-col items-start justify-center gap-16 pr-[max(1.5rem,3.5vw)] pl-6 md:flex">
                        <ScrollFeature progress={progress} start={0.6} side="right" feature={features[2]!} />
                        <ScrollFeature progress={progress} start={0.7} side="right" feature={features[3]!} />
                    </div>
                </div>
            </div>
            <section className="bg-white px-6 pt-20 pb-4 md:hidden">
                <div className="mx-auto flex max-w-md flex-col gap-12">
                    {features.map((feature) => (
                        <FeatureBlock key={feature.title} feature={feature} />
                    ))}
                </div>
            </section>
        </>
    );
}
