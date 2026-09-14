import { ArrowDown } from "lucide-react";
import Image from "next/image";

import wallpaper from "../tahoe-dark.webp";
import { DownloadLink } from "./download-link";
import { NotchContent } from "./notch-content";

export function Cta() {
    return (
        <section className="overflow-hidden border-b border-line bg-[#f5f1fa] px-6 pt-12 sm:px-8 sm:pt-14">
            <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-7">
                <div>
                    <h2 className="max-w-2xl font-display text-[38px] leading-[1.08] tracking-tight text-ink sm:text-[48px]">
                        Put your AI usage in the notch.
                    </h2>
                    <p className="mt-3 text-xs text-ink-3">Free and open source. macOS 14 or later.</p>
                </div>
                <DownloadLink className="inline-flex items-center gap-5 rounded-md bg-ink px-5 py-3 text-sm font-medium text-white transition-colors hover:bg-ink-2">
                    Download for macOS
                    <ArrowDown className="size-4" aria-hidden />
                </DownloadLink>
            </div>
            <div
                aria-hidden
                className="relative mx-auto mt-10 h-28 w-4/5 max-w-[440px] overflow-hidden rounded-t-2xl border-5 border-b-0 border-[#211b26] shadow-[0_0_60px_#a98acd20]"
            >
                <Image src={wallpaper} alt="" fill sizes="440px" className="object-cover object-top" />
                <div className="absolute top-0 left-1/2 h-[190px] w-[430px] origin-top -translate-x-1/2 scale-[0.35] rounded-b-[28px] bg-black px-5 pt-3 pb-5 shadow-xl sm:scale-50">
                    <NotchContent />
                </div>
            </div>
        </section>
    );
}
