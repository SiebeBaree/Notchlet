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
    livesIn: "The notch, expanding on hover.",
    tracks: "Claude Code, Codex, Cursor and OpenCode, three at a time.",
    reads: "Saved provider logins or pasted credentials, then provider usage APIs.",
    history:
        "Token counts, estimated API cost, a yearly activity graph and per-model usage from local logs and provider records.",
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
            "Compare CodexBar and Notchlet for provider support, usage history, sign-in and macOS compatibility.",
        source: { label: "its README", href: "https://github.com/steipete/CodexBar", checked: "Sep 13, 2026" },
        summary:
            "CodexBar monitors a broad range of AI providers from the menu bar. Notchlet focuses on Claude Code, Codex, Cursor and OpenCode, with usage gauges and history in the notch.",
        facts: {
            livesIn: "Menu bar. Linux desktop and CLI versions are also available.",
            tracks: "Codex, Claude, Cursor, Gemini, Copilot and many other providers.",
            reads: "Provider sessions, local files, API keys or browser cookies, depending on the provider.",
            history: "Local cost scans, credit balances and provider billing summaries where supported.",
            share: "PNG sharing is not documented in the README.",
            price: "Free.",
            source: "MIT on GitHub.",
            macos: "macOS 14 or later. Linux builds are also available.",
        },
        pickThem: [
            "You need more provider integrations.",
            "You prefer a menu bar app.",
            "You need provider billing summaries or a Linux version.",
        ],
        pickUs: [
            "You want usage in the notch.",
            "You want a local activity archive and PNG sharing.",
            "You use Claude Code, Codex, Cursor or OpenCode Go.",
        ],
    },
    {
        slug: "claudebar",
        name: "ClaudeBar",
        title: "Notchlet vs ClaudeBar",
        description:
            "Compare ClaudeBar and Notchlet for usage monitoring, provider support, history and macOS requirements.",
        source: { label: "its README", href: "https://github.com/tddworks/ClaudeBar", checked: "Sep 13, 2026" },
        summary:
            "ClaudeBar offers multi-provider quotas, account switching and menu bar, notch and Touch Bar views. Notchlet combines usage gauges, a local history archive and PNG sharing on macOS 14 or later.",
        facts: {
            livesIn: "Menu bar, with notch live activity and Touch Bar support.",
            tracks: "Claude, Codex, Gemini, Copilot, Cursor and other providers.",
            reads: "CLI credentials, local databases or provider APIs. Some integrations use browser cookies.",
            history: "Quota windows and pace warnings, with spend details for supported providers.",
            share: "Optional iPhone widgets through Notify!; PNG export is not documented.",
            price: "Free.",
            source: "MIT on GitHub.",
            macos: "macOS 15 or later.",
        },
        pickThem: [
            "You need providers such as Gemini or Copilot.",
            "You want Touch Bar support or iPhone quota widgets.",
        ],
        pickUs: ["You want a local usage archive and PNG sharing.", "You use macOS 14."],
    },
    {
        slug: "notchy",
        name: "Notchy",
        title: "Notchlet vs Notchy",
        description:
            "Compare Notchy and Notchlet for AI usage tracking, notch features, history and source availability.",
        source: { label: "notchy.dev", href: "https://notchy.dev/mac-ai-usage-tracker/", checked: "Sep 13, 2026" },
        summary:
            "Notchy combines AI usage with music controls, clipboard history and other Mac utilities. Notchlet focuses on coding-agent usage, history, notifications and secret scanning, with its source available on GitHub.",
        facts: {
            livesIn: "Notch, menu bar and desktop widgets.",
            tracks: "Local coding agents including Claude, Codex and Cursor, plus remote providers.",
            reads: "Existing CLI logins and local logs. Remote providers use credentials stored in the keychain.",
            history: "Usage windows, token counts, spend and pace projections.",
            share: "PNG sharing is not documented on the product page.",
            price: "Free, with donations accepted.",
            source: "No source repository linked from the product page.",
            macos: "macOS 13 or later.",
        },
        pickThem: [
            "You want music, clipboard and other utilities in the notch.",
            "You need more provider integrations or macOS 13 support.",
        ],
        pickUs: [
            "You want an app focused on coding-agent usage.",
            "You want to inspect or modify the source.",
            "You want to export your usage as a PNG.",
        ],
    },
    {
        slug: "ccusage",
        name: "ccusage",
        title: "Notchlet vs ccusage",
        description: "Compare ccusage terminal reports with Notchlet's usage gauges, local history and PNG sharing.",
        source: { label: "its README", href: "https://github.com/ccusage/ccusage", checked: "Sep 13, 2026" },
        summary:
            "ccusage generates detailed terminal reports from coding-agent logs. Notchlet reads provider usage limits and shows them alongside history in your Mac's notch.",
        facts: {
            livesIn: "Terminal, with a Claude Code status-line integration.",
            tracks: "Claude Code, Codex, OpenCode and other agent CLIs.",
            reads: "Local usage logs. Offline mode uses cached pricing data.",
            history: "Daily, weekly, monthly, session and five-hour block reports, with model breakdowns.",
            share: "JSON export and compact tables for screenshots.",
            price: "Free.",
            source: "MIT on GitHub.",
            macos: "Runs through Node.js or Bun on supported systems.",
        },
        pickThem: [
            "You want reports you can script or export as JSON.",
            "You need detailed filters or support for more agent logs.",
        ],
        pickUs: [
            "You want remaining limits reported by your provider.",
            "You prefer a native Mac interface.",
            "You want a local history archive and PNG sharing.",
        ],
    },
];

export function competitorFor(slug: string) {
    return competitors.find((competitor) => competitor.slug === slug);
}
