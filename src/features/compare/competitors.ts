// The same eight facts for Notchlet and for each tool it gets compared with. Competitor facts come from their own
// README or site on the date noted, and nothing here should say more than that source does.
export type Facts = {
    livesIn: string;
    tracks: string;
    reads: string;
    history: string;
    share: string;
    price: string;
    source: string;
    macos: string;
};

export const rows: { key: keyof Facts; label: string }[] = [
    { key: "livesIn", label: "Lives in" },
    { key: "tracks", label: "Tracks" },
    { key: "reads", label: "Reads" },
    { key: "history", label: "History and cost" },
    { key: "share", label: "Share" },
    { key: "price", label: "Price" },
    { key: "source", label: "Source" },
    { key: "macos", label: "Runs on" },
];

export const notchlet: Facts = {
    livesIn: "The notch. Nothing until you hover.",
    tracks: "Claude Code, Codex, Cursor and OpenCode, three at a time.",
    reads: "The login each CLI already saved, then the usage endpoint behind /usage or /status. Never browser cookies.",
    history:
        "Cost and tokens for today, 7 and 30 days, a 12 month activity graph and per-model tokens, from the logs on your Mac.",
    share: "A PNG of your numbers, graph and models.",
    price: "Free.",
    source: "MIT on GitHub.",
    macos: "macOS 14 or later.",
};

export type Competitor = {
    slug: string;
    name: string;
    title: string;
    description: string;
    source: { label: string; href: string; checked: string };
    summary: string;
    facts: Facts;
    pickThem: string[];
    pickUs: string[];
};

export const competitors: Competitor[] = [
    {
        slug: "codexbar",
        name: "CodexBar",
        title: "Notchlet vs CodexBar",
        description:
            "CodexBar tracks over 60 providers from the menu bar. Notchlet tracks four coding agents from the notch, with history and a share image. Which one fits.",
        source: { label: "its README", href: "https://github.com/steipete/CodexBar", checked: "Sep 4, 2026" },
        summary:
            "CodexBar is the wide one. If you pay for six AI subscriptions and want them all in one dropdown, it is the better tool, and it is MIT too. Notchlet tracks four agents and puts them in the notch instead of the menu bar, with a year of history and a share image.",
        facts: {
            livesIn: "The menu bar, with a dynamic bar icon.",
            tracks: "Over 60 providers, from Codex and Claude to OpenRouter and Ollama.",
            reads: "Provider config files, local JSONL logs, and browser cookies or local storage for the providers that need them.",
            history:
                "Local 7 and 30 day spend estimates, plus credit balances and billing dashboards where a provider has them.",
            share: "None listed.",
            price: "Free.",
            source: "MIT on GitHub.",
            macos: "macOS 14 or later. A CLI build also runs on Linux.",
        },
        pickThem: [
            "You use providers beyond Claude Code, Codex, Cursor and OpenCode.",
            "You want it in the menu bar, not the notch.",
            "You want credit balances and billing dashboards in one place.",
        ],
        pickUs: [
            "You run one to three coding agents and want the menu bar left alone.",
            "You want a year of usage history and a PNG to share.",
            "You do not want an app reading browser cookies. Notchlet never does.",
        ],
    },
    {
        slug: "claudebar",
        name: "ClaudeBar",
        title: "Notchlet vs ClaudeBar",
        description:
            "ClaudeBar shows quota windows for twelve providers from the menu bar. Notchlet shows four agents in the notch, with history, cost and a share image. Which one fits.",
        source: { label: "its README", href: "https://github.com/tddworks/ClaudeBar", checked: "Sep 4, 2026" },
        summary:
            "ClaudeBar covers twelve providers, including Gemini and Copilot, which Notchlet does not. It shows the windows and stops there. Notchlet covers four agents, adds history, cost at list price and a share image, and runs on macOS 14.",
        facts: {
            livesIn: "The menu bar, with a popover.",
            tracks: "Claude, Codex, Gemini, GitHub Copilot, Antigravity, Z.ai, Kimi, Kiro, Amp, OpenCode Go, Oh My Pi and Grok.",
            reads: "CLI credentials and tokens, local SQLite databases, and browser cookies for Kimi with Full Disk Access.",
            history: "Usage percentages and windows. No cost or history.",
            share: "None listed.",
            price: "Free.",
            source: "MIT on GitHub.",
            macos: "macOS 15 or later.",
        },
        pickThem: [
            "You use Gemini, Copilot, Antigravity or another agent Notchlet does not track.",
            "You want a menu bar popover.",
        ],
        pickUs: [
            "You want cost and tokens per day, not only percentages.",
            "You are on macOS 14.",
            "You want the numbers in the notch and nothing in the menu bar.",
        ],
    },
    {
        slug: "notchy",
        name: "Notchy",
        title: "Notchlet vs Notchy",
        description:
            "Notchy is a Dynamic Island for the Mac with AI usage as one panel. Notchlet is one app for your agent limits. Which one fits.",
        source: { label: "notchy.dev", href: "https://notchy.dev/mac-ai-usage-tracker/", checked: "Sep 4, 2026" },
        summary:
            "Notchy is a full Dynamic Island for the Mac, and AI tracking is one feature among twenty. If you want music controls and a clipboard in the notch too, get Notchy. Notchlet does one thing: your agent limits, your history and a share image, in an MIT repo you can read.",
        facts: {
            livesIn: "The notch, as a Dynamic Island with music, clipboard, timers and more.",
            tracks: "Claude Code, Codex, Cursor, Copilot, Antigravity, Windsurf, Zed and Amp from local logs, plus over 60 remote providers with stored credentials.",
            reads: "Local session logs for the agents, provider APIs with your stored credentials for the rest.",
            history: "Rate limits, tokens, spend for the day, 7 and 30 days, and pace projections.",
            share: "None listed.",
            price: "Free, funded by donations.",
            source: "No repository linked from notchy.dev.",
            macos: "macOS 13 or later.",
        },
        pickThem: [
            "You want a Dynamic Island, with AI usage as one of its panels.",
            "You use Copilot, Windsurf, Zed or Amp.",
            "You are on macOS 13.",
        ],
        pickUs: [
            "You want one small app that does one thing.",
            "You want to read the source before it reads your keychain.",
            "You want a PNG of your usage to share.",
        ],
    },
    {
        slug: "ccusage",
        name: "ccusage",
        title: "Notchlet vs ccusage",
        description:
            "ccusage reports what you spent, from the terminal. Notchlet shows what is left, in the notch, with a year of history. When to use which.",
        source: { label: "its README", href: "https://github.com/ryoppippi/ccusage", checked: "Sep 4, 2026" },
        summary:
            "ccusage is a report, Notchlet is a gauge. ccusage tells you what you spent, in detail, for more agents than Notchlet reads. It cannot tell you how much of the 5 hour window is left, because the logs do not know. Notchlet asks the provider for that and keeps a smaller history next to it.",
        facts: {
            livesIn: "Your terminal. Run npx ccusage@latest.",
            tracks: "Over 18 agent CLIs, from Claude Code and Codex to Gemini CLI and Copilot CLI.",
            reads: "The local usage logs each CLI writes. No network needed.",
            history:
                "Daily, weekly, monthly, session and 5 hour block reports with cost per model. Remaining rate-limit windows are not part of it.",
            share: "JSON export.",
            price: "Free.",
            source: "MIT on GitHub.",
            macos: "Anywhere Node runs.",
        },
        pickThem: [
            "You want a detailed report you can script or export.",
            "You use agents beyond Claude Code, Codex, Cursor and OpenCode.",
            "You are not on a Mac.",
        ],
        pickUs: [
            "You want to know what is left, not only what you spent.",
            "You want the number visible without a terminal command.",
            "You want history that survives Claude Code deleting its transcripts after 30 days.",
        ],
    },
];

export function competitorFor(slug: string) {
    return competitors.find((competitor) => competitor.slug === slug);
}
