import { ArrowRight } from "lucide-react";
import Image from "next/image";

import { supportedProviders } from "../supported-providers";

export function PacePreview() {
    return (
        <div className="flex items-center gap-4 rounded-[18px] bg-[#070707] px-5 py-4 text-white shadow-[0_14px_28px_rgba(25,18,38,0.13)]">
            <div className="relative size-[68px]">
                <svg viewBox="0 0 68 68" className="size-full -rotate-90">
                    <circle cx="34" cy="34" r="30" fill="none" stroke="#333338" strokeWidth="4" />
                    <circle
                        cx="34"
                        cy="34"
                        r="30"
                        fill="none"
                        stroke="#47ce7f"
                        strokeWidth="4"
                        strokeDasharray="136 189"
                        strokeLinecap="round"
                    />
                </svg>
                <div className="absolute inset-0 flex flex-col items-center justify-center">
                    <span className="text-base font-semibold">72%</span>
                    <span className="text-[9px] text-white/60">left</span>
                </div>
            </div>
            <div className="text-[10px] text-white/60">
                <span>Weekly usage</span>
                <strong className="my-1 block text-sm font-medium text-[#47ce7f]">On pace</strong>
                <span>Resets Saturday</span>
            </div>
        </div>
    );
}

export function LoginPreview() {
    return (
        <div className="flex flex-wrap items-center justify-center gap-2.5">
            {supportedProviders.slice(0, 3).map((provider) => (
                <span
                    key={provider.name}
                    className="flex size-11 items-center justify-center rounded-xl border border-line bg-white shadow-[0_7px_20px_rgba(32,19,48,0.07)]"
                >
                    <Image src={provider.icon} alt="" width={20} height={20} className="size-5 object-contain invert" />
                </span>
            ))}
            <ArrowRight className="size-4 text-ink-3/60" />
            <span className="flex size-11 items-center justify-center rounded-xl bg-ink">
                <span className="h-3 w-5 rounded-b-md bg-white" />
            </span>
        </div>
    );
}
