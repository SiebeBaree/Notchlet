"use client";

import { ChevronDown } from "lucide-react";
import { motion, useScroll, useTransform } from "motion/react";
import Image from "next/image";

import { useReducedMotion } from "@/lib/use-reduced-motion";

import { supportedProviders } from "../supported-providers";
import { DownloadLink } from "./download-link";

// Fades the copy off the desktop early in the scroll so the shrinking screen reads as a clean Mac.
export function HeroCopy() {
    const { scrollY } = useScroll();
    const reducedMotion = useReducedMotion();
    const opacity = useTransform(scrollY, [60, 420], [1, 0]);
    const y = useTransform(scrollY, [60, 420], [0, 48]);

    return (
        <motion.div
            style={{ opacity: reducedMotion ? 1 : opacity, y: reducedMotion ? 0 : y }}
            className="relative flex h-full flex-col items-center px-6 pt-[239px] pb-10 text-center sm:pt-[190px]"
        >
            <div className="my-auto flex w-full flex-col items-center">
                <h1 className="text-4xl leading-[1.05] font-bold tracking-[-0.022em] text-balance text-white [text-shadow:0_2px_24px_rgba(20,20,60,0.35),0_1px_3px_rgba(5,15,45,0.3)] sm:text-5xl md:text-[56px]">
                    Know before you hit the limit.
                </h1>
                <p className="mt-4 max-w-xl text-sm leading-relaxed text-balance text-white/85 [text-shadow:0_1px_10px_rgba(5,15,45,0.5)] sm:mt-5 sm:text-base">
                    Notchlet shows your Claude Code, Codex, Cursor and OpenCode usage in the notch, with the time until
                    each limit resets.
                </p>

                <p className="mt-6 text-xs font-semibold tracking-[0.16em] text-white/90 uppercase [text-shadow:0_1px_12px_rgba(5,15,45,0.5)] sm:mt-8">
                    Free and open source
                </p>
                <DownloadLink className="mt-6 rounded-lg bg-white px-6 py-3 text-[15px] font-medium text-black transition-opacity hover:opacity-90">
                    Download for macOS
                </DownloadLink>
                <p className="mt-3.5 text-[13px] text-white/85 [text-shadow:0_1px_10px_rgba(5,15,45,0.5)]">
                    macOS 14 or later
                </p>

                <div className="mt-7 flex flex-wrap items-center justify-center gap-x-5 gap-y-2 sm:mt-12 sm:flex-col sm:gap-4">
                    <p className="text-sm text-white/80 [text-shadow:0_1px_10px_rgba(5,15,45,0.5)]">Works with</p>
                    <ul className="flex flex-wrap items-center justify-center gap-x-7 gap-y-3">
                        {supportedProviders.map((provider) => (
                            <li
                                key={provider.name}
                                className="flex items-center gap-2.5 text-sm font-medium text-white [text-shadow:0_1px_10px_rgba(5,15,45,0.5)]"
                            >
                                <Image
                                    src={provider.icon}
                                    alt=""
                                    width={18}
                                    height={18}
                                    className="size-[18px] object-contain drop-shadow-[0_1px_6px_rgba(5,15,45,0.4)]"
                                />
                                {provider.name}
                            </li>
                        ))}
                    </ul>
                </div>
            </div>

            <div aria-hidden className="absolute bottom-6 left-1/2 hidden -translate-x-1/2 sm:block">
                <ChevronDown className="size-5 text-white/60 drop-shadow-[0_1px_6px_rgba(5,15,45,0.5)]" />
            </div>
        </motion.div>
    );
}
