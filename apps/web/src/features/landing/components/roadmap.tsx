import {
    ArrowUpRight,
    ChartNoAxesColumnIncreasing,
    Fingerprint,
    Plug,
    Users,
    MessageSquareWarning,
} from "lucide-react";

import { githubIssuesUrl } from "../links";

const roadmap = [
    {
        title: "Global leaderboard",
        description: "Compare your usage with other Notchlet users.",
        icon: ChartNoAxesColumnIncreasing,
    },
    {
        title: "AI personality",
        description: "Discover your AI personality from how you use your agents.",
        icon: Fingerprint,
    },
    {
        title: "Team leaderboard",
        description: "Battle your teammates on the usage leaderboard.",
        icon: Users,
    },
    {
        title: "Connect more providers",
        description: "Track more of your AI tools in Notchlet.",
        icon: Plug,
    },
    {
        title: "Angry counter",
        description: "Count the times you lose your temper with a model.",
        icon: MessageSquareWarning,
    },
];

export function Roadmap() {
    return (
        <section
            id="roadmap"
            aria-labelledby="roadmap-heading"
            className="border-b border-line px-5 py-14 sm:px-8 sm:py-16 lg:py-20"
        >
            <div className="mb-8 flex flex-wrap items-end justify-between gap-5">
                <div>
                    <h2
                        id="roadmap-heading"
                        className="text-[26px] font-semibold tracking-tight text-ink sm:text-[30px]"
                    >
                        Roadmap
                    </h2>
                    <p className="mt-3 text-[15px] text-ink-3">Planned features.</p>
                </div>
                <a
                    href={githubIssuesUrl}
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex items-center gap-1.5 text-xs font-medium text-brand transition-colors hover:text-ink"
                >
                    Suggest a feature <ArrowUpRight className="size-3.5" />
                </a>
            </div>
            <ul className="grid grid-cols-2 overflow-hidden rounded-lg border border-line md:grid-cols-5">
                {roadmap.map(({ title, description, icon: Icon }) => (
                    <li
                        key={title}
                        className="border-r border-b border-line px-4 pt-6 pb-7 last:col-span-2 last:border-0 even:border-r-0 md:border-b-0 md:last:col-span-1 md:even:border-r"
                    >
                        <div aria-hidden className="flex h-16 items-center">
                            <Icon className="size-9 text-[#8965c8]" strokeWidth={1.25} />
                        </div>
                        <h3 className="text-[13px] font-semibold tracking-tight text-ink">{title}</h3>
                        <p className="mt-2 text-xs leading-relaxed text-ink-3">{description}</p>
                    </li>
                ))}
            </ul>
            <div className="mt-6 flex flex-wrap items-center justify-between gap-5">
                <p className="text-xs text-ink-3">Have a feature in mind? Add it on GitHub.</p>
                <a
                    href={githubIssuesUrl}
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex items-center gap-3 rounded-md bg-ink px-4 py-2.5 text-xs font-medium text-white transition-colors hover:bg-ink-2"
                >
                    Open an issue <ArrowUpRight className="size-3.5" />
                </a>
            </div>
        </section>
    );
}
