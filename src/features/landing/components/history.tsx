import { type Feature, FeatureBlock } from "./features";

const ranges = [
    { label: "Today", cost: "$12.40", tokens: "9.8M" },
    { label: "7 days", cost: "$96.20", tokens: "78M" },
    { label: "30 days", cost: "$412.10", tokens: "340M", selected: true },
];

const models = [
    { name: "claude-opus-5", input: "210M", output: "1.9M" },
    { name: "claude-fable-5-1", input: "98M", output: "1.1M" },
    { name: "claude-sonnet-5", input: "24M", output: "310K" },
    { name: "claude-haiku-4-5", input: "6.1M", output: "48K" },
];

const months = ["Sep", "Oct", "Nov", "Dec", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug"];

// The app's activity palette: an empty day, then four levels darkest to brightest.
const levels = ["#232325", "#12407a", "#1f5ead", "#3887e6", "#87b5f0"];

const shipped: Feature[] = [
    {
        title: "Kept after Claude Code forgets",
        description:
            "Claude Code deletes its transcripts after 30 days. Notchlet seals each finished day into its own archive, so the graph keeps growing from the day you installed it.",
        badges: [{ label: "Claude Code" }, { label: "Codex" }, { label: "Cursor" }, { label: "OpenCode" }],
    },
    {
        title: "Share it as a PNG",
        description:
            "The share icon renders your cost or tokens, the graph and the models you used on black glass with the notch cut out of the top. Copy, paste it into a post.",
        badges: [{ label: "PNG" }, { label: "Copy or save" }],
    },
    {
        title: "A verdict, not a number",
        description:
            "Every ring carries a tick for an even burn. Ahead of it says Plenty. Behind it says how early the window runs dry.",
        badges: [{ label: "Plenty" }, { label: "On pace" }, { label: "Empty 1h 20m early" }],
    },
];

// A year of plausible activity, seeded so the server draws the same grid every time.
function activity() {
    let seed = 7;
    const random = () => {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        return seed / 2147483648;
    };
    return Array.from({ length: 53 * 7 }, (_, index) => {
        const week = Math.floor(index / 7);
        const weekday = index % 7;
        const weekend = weekday === 0 || weekday === 6;
        // Busier toward the right edge, which is today.
        const heat = 0.15 + (week / 52) * 0.8;
        const roll = random();
        const level = (weekend && roll < 0.7) || roll > heat ? 0 : 1 + Math.floor(random() * 4);
        return { day: `w${week}d${weekday}`, level };
    });
}

// The history pane as the notch shows it, drawn in HTML rather than screenshotted so it stays crisp at every size.
function HistoryPane() {
    return (
        <div className="mx-auto w-full max-w-[430px] rounded-[28px] bg-black p-5 text-white shadow-[0_30px_70px_rgba(5,15,40,0.35)]">
            <div className="flex items-center gap-1 text-[10.5px]">
                {["All", "Claude", "Codex"].map((chip, index) => (
                    <span
                        key={chip}
                        className={`rounded-full px-2 py-0.5 ${index === 0 ? "bg-white/12 text-white" : "text-white/55"}`}
                    >
                        {chip}
                    </span>
                ))}
            </div>
            <div className="mt-3 grid grid-cols-3">
                {ranges.map((range) => (
                    <div key={range.label} className="flex flex-col">
                        <span className={`text-[10.5px] ${range.selected ? "text-white/85" : "text-white/50"}`}>
                            {range.label}
                        </span>
                        <span className="mt-0.5 text-[20px] leading-tight font-semibold">{range.cost}</span>
                        <span className="text-[10.5px] text-white/55">{range.tokens} tokens</span>
                    </div>
                ))}
            </div>
            <hr className="my-3 border-white/15" />
            <div className="flex items-center gap-2.5 text-[11px]">
                <span>Activity</span>
                <span className="text-white/55">Spend</span>
                <span className="ml-auto text-[10px] text-white/40">Tokens, 12 months</span>
            </div>
            <div aria-hidden className="mt-2 grid grid-cols-12 text-[10px] text-white/40">
                {months.map((month) => (
                    <span key={month}>{month}</span>
                ))}
            </div>
            <div aria-hidden className="mt-1 grid auto-cols-fr grid-flow-col grid-rows-7 gap-[2px]">
                {activity().map((cell) => (
                    <span
                        key={cell.day}
                        className="aspect-square rounded-[1.5px]"
                        style={{ background: levels[cell.level] }}
                    />
                ))}
            </div>
            <hr className="my-3 border-white/15" />
            <table className="w-full text-[11px]">
                <thead className="text-[10px] text-white/45">
                    <tr>
                        <th className="pb-1 text-left font-normal">Model</th>
                        <th className="w-[60px] pb-1 text-right font-normal">Input</th>
                        <th className="w-[60px] pb-1 text-right font-normal">Output</th>
                    </tr>
                </thead>
                <tbody className="text-white/85">
                    {models.map((model) => (
                        <tr key={model.name}>
                            <td className="py-0.5">{model.name}</td>
                            <td className="py-0.5 text-right">{model.input}</td>
                            <td className="py-0.5 text-right">{model.output}</td>
                        </tr>
                    ))}
                </tbody>
            </table>
            <p className="mt-1 text-[10px] text-white/55">2 more</p>
            <p className="mt-3 text-[10px] text-white/40">Cost at API list prices · History since Aug 31</p>
        </div>
    );
}

export function History() {
    return (
        <section className="border-t border-line bg-white px-6 py-28">
            <div className="mx-auto max-w-6xl">
                <h2 className="max-w-2xl text-[26px] leading-[1.25] font-semibold tracking-tight text-ink sm:text-[30px]">
                    What you used. <span className="text-ink-3">Not only what is left.</span>
                </h2>
                <p className="mt-4 max-w-xl text-[15px] leading-relaxed text-ink-3">
                    Click any gauge and the notch turns into history: cost and tokens for today, 7 days and 30 days, a
                    year of activity and every model with its input and output. Read from the logs each agent already
                    keeps.
                </p>
                <div className="mt-14 grid gap-16 lg:grid-cols-2 lg:items-center">
                    <HistoryPane />
                    <div className="flex flex-col gap-12">
                        {shipped.map((feature) => (
                            <FeatureBlock key={feature.title} feature={feature} />
                        ))}
                    </div>
                </div>
            </div>
        </section>
    );
}
