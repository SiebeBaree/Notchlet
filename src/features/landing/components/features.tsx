export const features = [
    {
        title: "Usage and reset times",
        description: "See the limits your provider reports and when each one resets.",
    },
    {
        title: "Already signed in",
        description: "Notchlet uses the provider logins on your Mac.",
    },
    {
        title: "Free and open source",
        description: "MIT licensed. Read the code or build it yourself.",
    },
    {
        title: "A native macOS app",
        description: "Usage lives at the top of your screen while you work.",
    },
] as const;

export function FeatureBlock({
    feature,
    align = "left",
}: {
    feature: (typeof features)[number];
    align?: "left" | "right";
}) {
    return (
        <div
            className={`flex max-w-xs flex-col ${align === "right" ? "items-end text-right" : "items-start text-left"}`}
        >
            <h3 className="text-base font-semibold tracking-tight text-ink">{feature.title}</h3>
            <p className="mt-2 text-sm leading-relaxed text-ink-3">{feature.description}</p>
        </div>
    );
}
