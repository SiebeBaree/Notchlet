"use client";

import { ChevronDown } from "lucide-react";
import { motion, useScroll, useTransform } from "motion/react";
import Image from "next/image";

import { Countdown } from "./countdown";
import { SignupForm } from "./signup-form";

const providers = [
    { name: "Claude Code", icon: "/claude-ai-icon.svg" },
    { name: "Codex", icon: "/openai_dark.svg" },
] as const;

// Fades the copy off the desktop early in the scroll so the shrinking screen reads as a clean Mac.
export function HeroCopy() {
    const { scrollY } = useScroll();
    const opacity = useTransform(scrollY, [60, 420], [1, 0]);
    const y = useTransform(scrollY, [60, 420], [0, 48]);

    return (
        <motion.div
            style={{ opacity, y }}
            className="relative flex h-full flex-col items-center px-6 pt-[215px] pb-10 text-center sm:pt-[190px]"
        >
            <div className="my-auto flex w-full flex-col items-center">
                <h1 className="text-4xl leading-[1.05] font-bold tracking-[-0.022em] text-balance text-white [text-shadow:0_2px_24px_rgba(20,20,60,0.35),0_1px_3px_rgba(5,15,45,0.3)] sm:text-5xl md:text-[56px]">
                    Know before you hit the limit.
                </h1>
                <p className="mt-4 max-w-xl text-sm leading-relaxed text-balance text-white/85 [text-shadow:0_1px_10px_rgba(5,15,45,0.5)] sm:mt-5 sm:text-base">
                    Notchlet keeps your Claude Code and Codex usage in the notch, so the five hour window never runs out
                    on you mid task.
                </p>

                <p className="mt-6 text-xs font-semibold tracking-[0.16em] text-white/90 uppercase [text-shadow:0_1px_12px_rgba(5,15,45,0.5)] sm:mt-8">
                    Free and open source
                </p>
                <div className="mt-4">
                    <Countdown />
                </div>
                <p className="mt-3.5 text-[13px] text-white/85 [text-shadow:0_1px_10px_rgba(5,15,45,0.5)]">
                    Launches Monday August 31, 13:00 CEST
                </p>

                <div className="mt-7 w-full max-w-sm">
                    <SignupForm />
                </div>

                <div className="mt-7 flex flex-wrap items-center justify-center gap-x-5 gap-y-2 sm:mt-12 sm:flex-col sm:gap-4">
                    <p className="text-sm text-white/80 [text-shadow:0_1px_10px_rgba(5,15,45,0.5)]">Works with</p>
                    <ul className="flex flex-wrap items-center justify-center gap-x-7 gap-y-3">
                        {providers.map((provider) => (
                            <li
                                key={provider.name}
                                className="flex items-center gap-2.5 text-sm font-medium text-white [text-shadow:0_1px_10px_rgba(5,15,45,0.5)]"
                            >
                                <Image
                                    src={provider.icon}
                                    alt=""
                                    width={18}
                                    height={18}
                                    className="h-[18px] w-auto drop-shadow-[0_1px_6px_rgba(5,15,45,0.4)]"
                                />
                                {provider.name}
                            </li>
                        ))}
                    </ul>
                </div>
            </div>

            <div
                aria-hidden
                className="absolute bottom-6 left-1/2 hidden -translate-x-1/2 animate-[hint-bob_2.4s_ease-in-out_infinite] motion-reduce:animate-none sm:block"
            >
                <ChevronDown className="size-5 text-white/60 drop-shadow-[0_1px_6px_rgba(5,15,45,0.5)]" />
            </div>
        </motion.div>
    );
}
