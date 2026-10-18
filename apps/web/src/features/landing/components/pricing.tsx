import { ArrowUpRight, Check } from "lucide-react";

import { cn } from "@/lib/utils";

import { githubUrl, sponsorUrl } from "../links";
import { DownloadLink } from "./download-link";

const plans = [
    {
        name: "Free",
        note: "forever",
        features: ["Every feature", "All updates", "GTA VI not included"],
        button: "Download",
    },
    {
        name: "Pro",
        note: "per month, billed never",
        features: ["Everything in Free", "Nothing else", "GTA VI not included"],
        button: "Download anyway",
    },
    {
        name: "Source",
        note: "MIT licensed",
        features: ["Clone the repo", "Change anything", "Build it yourself"],
        button: "View on GitHub",
        href: githubUrl,
    },
];

export function Pricing() {
    return (
        <section
            id="pricing"
            aria-labelledby="pricing-heading"
            className="border-b border-line px-5 py-14 sm:px-8 sm:py-16 lg:py-20"
        >
            <h2 id="pricing-heading" className="text-[26px] font-semibold tracking-tight text-ink sm:text-[30px]">
                Free and open source.
            </h2>
            <p className="mt-3 text-[15px] text-ink-3">All features are included. There is no paid tier.</p>
            <div className="mt-8 grid overflow-hidden rounded-lg border border-line md:grid-cols-3">
                {plans.map((plan) => {
                    const pro = plan.name === "Pro";
                    const buttonClass = cn(
                        "mt-auto inline-flex w-full items-center justify-center gap-2 rounded-md px-4 py-3 text-xs font-medium transition-colors",
                        pro
                            ? "bg-ink text-white hover:bg-ink-2"
                            : "border border-line bg-white text-ink hover:bg-brand-soft/60",
                    );
                    return (
                        <div
                            key={plan.name}
                            className={cn(
                                "flex flex-col items-start border-b border-line p-7 last:border-0 md:border-r md:border-b-0 lg:p-8",
                                pro && "bg-[#f5f1fc] shadow-[inset_0_3px_#9d7ade]",
                            )}
                        >
                            <h3 className="text-[15px] font-semibold text-ink">{plan.name}</h3>
                            <p className="mt-5 font-display text-[60px] leading-none tracking-tight text-ink">$0</p>
                            <p className="mt-2 text-xs text-ink-3">{plan.note}</p>
                            <ul className="my-7 flex flex-col gap-3 text-xs text-ink-2">
                                {plan.features.map((feature) => (
                                    <li key={feature} className="flex items-center gap-2.5">
                                        <Check className="size-3.5 text-brand" aria-hidden />
                                        {feature}
                                    </li>
                                ))}
                            </ul>
                            {plan.href ? (
                                <a href={plan.href} target="_blank" rel="noreferrer" className={buttonClass}>
                                    {plan.button}
                                    <ArrowUpRight className="size-3.5" aria-hidden />
                                </a>
                            ) : (
                                <DownloadLink className={buttonClass}>{plan.button}</DownloadLink>
                            )}
                        </div>
                    );
                })}
            </div>
            <p className="mt-5 text-xs text-ink-3">
                Want to support development?{" "}
                <a
                    href={sponsorUrl}
                    target="_blank"
                    rel="noreferrer"
                    className="text-brand underline underline-offset-4 transition-colors hover:text-ink"
                >
                    Sponsor me on GitHub
                </a>
                .
            </p>
        </section>
    );
}
