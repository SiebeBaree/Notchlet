import { githubUrl } from "../links";

export type Feature = {
    title: string;
    description: string;
    badges: { label: string; href?: string }[];
};

export const features: Feature[] = [
    {
        title: "Every limit at a glance",
        description: "The five hour window, the weekly cap and each model, with the time until the next reset.",
        badges: [{ label: "5h window" }, { label: "Weekly" }, { label: "Per model" }],
    },
    {
        title: "No account, no sign up",
        description:
            "Notchlet asks your provider how much of your plan is left. That is the whole conversation. Nothing you write ever leaves your Mac.",
        badges: [{ label: "No account" }, { label: "Usage only" }],
    },
    {
        title: "Open source",
        description: "MIT on GitHub. Read it, build it yourself or fork it and make it worse.",
        badges: [{ label: "MIT" }, { label: "GitHub", href: githubUrl }],
    },
    {
        title: "Idles at ~0% CPU",
        description: "A small native app that sleeps until you hover. Your battery will not notice it.",
        badges: [{ label: "Native" }, { label: "Apple silicon" }],
    },
];

const badgeClass = "rounded-md bg-brand-soft px-2.5 py-0.5 font-mono text-[12px] font-medium text-brand";

export function FeatureBlock({ feature, align = "left" }: { feature: Feature; align?: "left" | "right" }) {
    const alignClass = align === "right" ? "items-end text-right" : "items-start text-left";
    return (
        <div className={`flex max-w-xs flex-col ${alignClass}`}>
            <h3 className="text-[16px] font-semibold tracking-tight text-ink">{feature.title}</h3>
            <p className="mt-2 text-sm leading-relaxed text-ink-3">{feature.description}</p>
            <div className="mt-3.5 flex flex-wrap gap-1.5">
                {feature.badges.map((badge) =>
                    badge.href ? (
                        <a
                            key={badge.label}
                            href={badge.href}
                            target="_blank"
                            rel="noreferrer"
                            className={`${badgeClass} transition-colors hover:bg-brand hover:text-white`}
                        >
                            {badge.label}
                        </a>
                    ) : (
                        <span key={badge.label} className={badgeClass}>
                            {badge.label}
                        </span>
                    ),
                )}
            </div>
        </div>
    );
}
