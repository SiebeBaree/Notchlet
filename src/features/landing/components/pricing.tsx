import { Check } from "lucide-react";

import { githubUrl, sponsorUrl } from "../links";
import { DownloadLink } from "./download-link";

const plans = [
    {
        name: "Free",
        note: "forever",
        features: ["Every feature", "Every future feature", "GTA VI not included"],
        button: "Download",
        buttonClass: "border border-line bg-white text-ink hover:bg-brand-soft/60",
        highlighted: false,
    },
    {
        name: "Pro",
        note: "per month, billed never",
        features: ["Everything in Free", "Nothing else", "GTA VI not included"],
        button: "Download anyway",
        buttonClass: "bg-ink text-white hover:bg-ink-2",
        highlighted: true,
    },
    {
        name: "Source",
        note: "MIT licensed",
        features: ["Clone the repo", "Change anything"],
        button: "View on GitHub",
        buttonClass: "border border-line bg-white text-ink hover:bg-brand-soft/60",
        highlighted: false,
        href: githubUrl,
    },
] as const;

const buttonBase = "mt-9 block cursor-pointer rounded-md px-5 py-2.5 text-center text-sm font-medium transition-colors";

export function Pricing() {
    return (
        <section className="bg-white px-6 py-28">
            <div className="mx-auto max-w-6xl">
                <h2 className="max-w-2xl text-[26px] leading-[1.25] font-semibold tracking-tight text-ink sm:text-[30px]">
                    Pricing. <span className="text-ink-3">The hardest decision on this page.</span>
                </h2>
                <p className="mt-4 max-w-xl text-[15px] leading-relaxed text-ink-3">
                    Notchlet is free and open source. Three plans, one price.
                </p>
                <div className="mt-14 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
                    {plans.map((plan) => (
                        <div
                            key={plan.name}
                            className={`flex flex-col rounded-xl border bg-white p-8 ${
                                plan.highlighted
                                    ? "border-brand/30 shadow-[0_16px_48px_-16px_rgba(79,46,204,0.28)]"
                                    : "border-line shadow-[0_8px_24px_-12px_rgba(79,46,204,0.16)]"
                            }`}
                        >
                            <div className="flex items-center justify-between">
                                <h3 className="text-[15px] font-semibold tracking-tight text-ink">{plan.name}</h3>
                                {plan.highlighted && (
                                    <span className="rounded-md bg-brand-soft px-2.5 py-0.5 font-mono text-[11px] font-medium text-brand">
                                        Most popular
                                    </span>
                                )}
                            </div>
                            <p className="mt-5 flex items-baseline gap-2.5">
                                <span className="font-display text-[54px] leading-none text-ink">$0</span>
                                <span className="text-[13px] text-ink-3">{plan.note}</span>
                            </p>
                            <ul className="mt-8 flex flex-col gap-3">
                                {plan.features.map((feature) => (
                                    <li key={feature} className="flex items-center gap-2.5 text-sm text-ink-2">
                                        <Check aria-hidden className="size-4 shrink-0 text-brand" />
                                        {feature}
                                    </li>
                                ))}
                            </ul>
                            {/* The source card leaves the site, the other two start the download. */}
                            <div className="mt-auto">
                                {"href" in plan ? (
                                    <a
                                        href={plan.href}
                                        target="_blank"
                                        rel="noreferrer"
                                        className={`${buttonBase} ${plan.buttonClass}`}
                                    >
                                        {plan.button}
                                    </a>
                                ) : (
                                    <DownloadLink className={`${buttonBase} ${plan.buttonClass}`}>
                                        {plan.button}
                                    </DownloadLink>
                                )}
                            </div>
                        </div>
                    ))}
                </div>
                <p className="mt-8 text-[13px] text-ink-3">
                    Or{" "}
                    <a
                        href={sponsorUrl}
                        target="_blank"
                        rel="noreferrer"
                        className="font-medium text-brand underline underline-offset-4 transition-colors hover:text-ink"
                    >
                        sponsor me on GitHub
                    </a>
                    , if you insist.
                </p>
            </div>
        </section>
    );
}
