import { githubIssuesUrl } from "../links";

// "Local" and "Opt in" answer the question the privacy block raises: anything that reads your chats does it on your
// Mac, and anything that leaves the device is a choice you make.
const roadmap = [
    { title: "Leaked keys in your chats", sub: "a scan of your transcripts for API keys", tag: "Local" },
    { title: "Alerts when an agent is waiting on you" },
    { title: "Angry counter", sub: "how often you lose it at the model", tag: "Local" },
    { title: "Global leaderboard", sub: "anonymous unless you make a profile", tag: "Opt in" },
    { title: "Your AI personality", sub: "when you work, your most used phrases, who you are in chats", tag: "Opt in" },
] as const;

export function Roadmap() {
    return (
        <section className="border-y border-line bg-white px-6 py-28">
            <div className="mx-auto max-w-6xl">
                <h2 className="max-w-2xl text-[26px] leading-[1.25] font-semibold tracking-tight text-ink sm:text-[30px]">
                    What ships next is up to you.
                </h2>
                <p className="mt-4 max-w-xl text-[15px] leading-relaxed text-ink-3">
                    Nothing below is locked in. Tell me which one you actually want.
                </p>
                <ul className="mt-14 grid gap-px overflow-hidden rounded-xl border border-line bg-line sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-5">
                    {roadmap.map((item, index) => (
                        <li key={item.title} className="flex flex-col bg-white p-6">
                            <span className="flex items-center justify-between">
                                <span className="font-mono text-[11px] font-medium text-brand">
                                    {String(index + 1).padStart(2, "0")}
                                </span>
                                {"tag" in item && (
                                    <span className="rounded-md bg-brand-soft px-2 py-0.5 font-mono text-[10px] font-medium text-brand">
                                        {item.tag}
                                    </span>
                                )}
                            </span>
                            <span className="mt-3 text-[15px] font-semibold tracking-tight text-ink">{item.title}</span>
                            {"sub" in item && (
                                <span className="mt-1.5 block text-[13px] leading-relaxed text-ink-3">{item.sub}</span>
                            )}
                        </li>
                    ))}
                </ul>
                <div className="mt-12 flex flex-wrap items-center gap-x-5 gap-y-4">
                    <a
                        href={githubIssuesUrl}
                        target="_blank"
                        rel="noreferrer"
                        className="rounded-md bg-ink px-5 py-2.5 text-sm font-medium text-white transition-colors hover:bg-ink-2"
                    >
                        Tell me what to build first
                    </a>
                    <p className="text-[13px] text-ink-3">Open an issue. I read all of them.</p>
                </div>
            </div>
        </section>
    );
}
